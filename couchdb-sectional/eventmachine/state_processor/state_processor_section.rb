module StateProcessor
  module StateProcessorSection
    include StateProcessor::StateProcessorExceptions
    include StateProcessor::StateProcessorMatchConstant
    extend ActiveSupport::Concern  
   
    class NoMatchException < StandardError; end
    class PauseProcessing < StandardError
      attr_accessor :value
    end

    class ArgumentMatches < Array
      attr_reader :save
      def initialize
        @save = [] 
        super
      end
    end

    module ClassMethods
      class << self
        attr_accessor :protocol
        attr_accessor :state
        attr_accessor :commands
        attr_accessor :worker

        def inspect
          hex_id = "%x" % self.object_id << 1
          "#<#{self.worker.to_s}ProcessorClass:0x#{hex_id} protocol: #{self.protocol}>" 
        end
      end
    end
    
    OPTLIST = [ :command, :executed_command, :origin, :result, :callingstate, :current_command, :worker ]

    OPERATORS = [:_, :*]
    
    included do 
      OPTLIST.collect { |opt| attr_accessor opt }
    end
    
    def options= opts
      OPTLIST.each do |opt|
        self.send "#{opt}=", opts[opt] if opts.has_key? opt
      end
    end

    def options 
      OPTLIST.inject({}) do |memo,k|
        memo[k] = self.send "#{k}"
        memo
      end
    end
    
    def callchain
      Enumerator.new do |y|
        y.yield self
        if @callingstate
          call = @callingstate 
          while call do
            y.yield call 
            call = call.callingstate
          end
        end
      end
    end


    def initialize callingstate=nil, opts = {}
      # who knew - you can't call an attr_accessor from initialize
      self.options = callingstate.options.merge opts if callingstate
      @callingstate = callingstate
      @previous_states = []
      @processors = {}
      @command_block = self.class.commands
      @executed_command = []
      @previous_command_blocks = []
      @worker = self.class.worker.new
      self
    end

    def switch_state state, opts = {}, &block
      protocol = opts.has_key?(:protocol) ? opts[:protocol] : self.class.protocol
      top = opts.has_key?(:top) ? opts[:top] : false
      begin
        state_class = StateProcessorFactory[state] 
      rescue StateProcessorInvalidState
        raise unless block_given?
        # switch the worker object for the duration of the yield
        # is that really the prettiest way to do this?
        old_worker, self.class.worker = self.class.worker, state
        state = yield
        self.class.worker = old_worker
        retry 
      end
      #TODO investigate whether flatten is appropriate here, or if we should do a single
      # level flatten, or perhaps just leave it to the calling state
      # to prepare our arguments for us.
      # actually, we should leave it to the protocol.  there should be 
      # prep command method in the protocol
      
      # we have our state_class now - we should check to see if we've already instantiated processors
      # underneath ourselves
      # seriously?
      processor = if @processors.has_key?(state_class) then
        @processors[state_class]
      else
        @processors[state_class] = state_class.new(self,opts)
      end
      @result = processor.process(@command.flatten,top)

    end

    def dispatch obj, m, *args, &block
      if obj and obj.respond_to? m
        obj.send m, *args, &block
      else
        raise StateProcessorCannotPerformAction.new( 
            "Could not perform action #{m} in #{self.class.inspect} with worker #{self.class.worker}")
      end
    end
    private :dispatch

    # dispatches called methods to the current worker object
    # this needs a better implementation
    def method_missing(m, *args, &block)
      if self.worker.respond_to? m 
        dispatch(self.worker, m, *args, &block)
      else
        raise NameError, "undefined local variable or method `#{m}' for #{self.inspect}" 
      end
    end
    
    # a method which runs a compiled function in the context of a method
    # used for callbacks / contiuation passing, etc.
    def run *args, &block
      @current_command.map do |c|
        args.unshift c.to_sym
      end
      self.worker.run *args, &block         
    end
    
    # A convience method for sending the current command to an instance of the worker object
    def execute cmd=nil, *args, &block
      if block_given?
        # i can't think of a reason why you'd need to pass args in if you gave
        # it a block
        dispatch(self.class.worker.instance_eval(&block))
      else
        ex = ArgumentError.new('Execute must be passed a method name or block')
        raise ex unless cmd.kind_of? Symbol
        begin 
          dispatch(self.class.worker, cmd, *args)
        rescue StateProcessorCannotPerformAction => e
          raise
        end
      end
    end

    
    def _(arg=nil)
      return StateProcessorMatch unless arg
      lambda do |a| 
        break a == arg ? StateProcessorMatch : StateProcessorNoMatch 
      end
    end
    alias :anywhere :_
    alias :anything :_

    def _!(arg=nil)
      return StateProcessorMatch unless arg
      lambda do |a|
        break a == arg ? StateProcessorConsume : StateProcessorNoMatch 
      end
    end
    alias :save_anywhere :_!
    alias :save_anything :_!

    def match_args(matchlist,cmd)
      matches = ArgumentMatches.new 
      
      match_proc,cmd_match = matchlist.partition do |m|
        true if m.is_a? Proc
      end

      indifferent_match = lambda do |arg,match|
        if match.is_a? Symbol
          return arg.to_sym if arg.to_sym == match
        else
          return arg if arg == match
        end
        false
      end

      cmd_match.each_with_index do |arg,i|
        if arg == StateProcessorMatch
          matches << cmd[i] 
        elsif arg == StateProcessorConsume
          matches.save << cmd[i] 
        elsif (mtcarg = indifferent_match.call(arg, cmd[i]))
          matches << arg
        end
      end

      match_proc.each do |mp|
        cmd.each do |c|
          match_action = mp.call(c)
          if match_action == StateProcessorMatch
            matches << arg
          elsif match_action == StateProcessorConsume
            matches.save << arg
          end
        end
      end

      ret_matches = []
      ret_matches = matches + matches.save
      raise NoMatchException unless ret_matches.size > 0
      ret_matches 
    end
    private :match_args

    def on *args, &block
      #TODO, rewrite so it stores commands and does a lookup at runtime rather than
      #running through all of the commands
      # this is O(N) since it calls this method once for each "on" block.
      # I could get it instead to store them in a lut, and then executed based
      # on the value of "matched" which would be better
      #
      #
      # REFACTOR
      @previous_command_blocks << @command_block
      @command_block = block 
      
      cmd = @command.dup
      begin 
        matched = match_args(args,cmd)
        raise NoMatchException unless matched
        (@current_command = @command.shift(matched.size)) if matched.size > 0
        if block_given?
          raise NoMatchException if @arity_match && block.arity != @command.size 
          result = yield *(@command)
          set_executed_commands
        else
          # not sure this works the way it ought to
          result = dispatch(self.worker, 
            (@current_command * '_').to_sym, *(@command))
        end
        @result = result.nil? ? @result : result
        stop_with @result if @stop_after
      rescue NoMatchException => e
        @command.unshift *(@current_command)
      end
      @command_block = @previous_command_blocks.pop
      @result
    end

    # call context in the worker 
    def context &block
      self.class.worker.context &block  
    end

    # call context in the worker, supressing the overwrite exception
    def context! &block
      self.class.worker.context! &block
    end


    # i am not exactly sure you should ever do this.
    def exit e
      raise StateProcessorExit, e
    end
 
    def on_error error=nil, &block
      self.class.send :define_method, :report_error, &block
    end

    # equivalent to "return"
    def stop_with result
      e = LocalJumpError.new
      #subvert! cheat! 
      e.instance_eval do
        @reason = :return
        @exit_value = result
      end
      raise e 
    end

    def arity_match
      begin 
        @arity_match = true
        yield
      ensure
        @arity_match = false
      end
    end
    alias :matching_arity :arity_match
      

    def return_after 
      begin
        @stop_after = true
        yield
      ensure
        @stop_after = false
      end
    end
    alias :stopping_after :return_after

    def pass result, &block
      
      callchain.each do |c|
        c.instance_exec @current_state do |cs|
          @previous_states << @current_state
          @current_state = cs
        end
      end
      # next time, control will be passed to our calling block or our block
      @command_block = if block_given? then block else @previous_command_blocks.pop end
      set_executed_commands
        
      # unwind to the command block 
      throw :pause_processing, result
    end

    def reset_states
      #called by return to clear internal block stock
      callchain.each do |c|
        c.instance_exec do
          # go to the front of the line!
          @command_block = @previous_command_blocks.first
          @previous_command_blocks = []
          ps = @previous_states.pop
          @current_state = ps
        end
      end
    end
    private :reset_states

    def consume_command! num=1
      @command.shift(num)
    end

    def set_executed_commands
      @command.unshift(*@current_command)
      (@executed_commands << @current_command.shift) if @current_command
      @current_command = nil
    end 
    private :set_executed_commands
  
    # simple stub implementation error handle.
    # we need to figure out which protocol object called me and pass it back the error
    def error e
      $stderr.puts e 
    end

    def process cmd, top=true
      @executed_commands = []
      puts cmd 
      @command = cmd

     # define the main working block
      workf = lambda do 
        begin
          unless @current_state 
            @current_state = Fiber.new do
              loop do
                # this makes the stack unwind to the top of the current command block
                @result = catch :pause_processing do 
                  @result = instance_exec(@command,&(@command_block))
                end
                raise StateProcessorDoesNotRespond unless @executed_commands.size > 0
                Fiber.yield @result
              end
            end
          end
          @current_state.resume
        rescue FiberError
          error "dead fiber"
          @current_state = false
          retry
        rescue LocalJumpError => e
          if e.reason == :return
            reset_states
            set_executed_commands 
            throw :stop_processing, e.exit_value 
          end
        rescue StateProcessorError => e
          raise e
        rescue StandardError => e
          if methods.include? :report_error then
            puts 'calling report error'
            report_error e
          else
            puts 'default error handler'
            error e
          end
        rescue StateProcessorDoesNotRespond => e
          reset_states rescue nil
          raise e
        rescue => e
          error "some unknown error" 
          reset_states rescue nil
          set_executed_commands rescue nil
          raise e
        # perhaps i could use an ensure here to reset_states and set_executed
        end
      end
      
      if top
        @result = catch :stop_processing do 
          workf.call
        end
      else
        @result = workf.call
      end
      #-- RAISING STOP PROCESSING WILL COME BACK TO HERE--#
      @result
    end
   
    def inspect
       hex_id = "%x" % self.object_id << 1
       "#<#{self.class.worker.to_s}Processor:0x#{hex_id} protocol: #{self.class.protocol}>"
    end
  end
end
