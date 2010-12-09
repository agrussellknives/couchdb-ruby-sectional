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
      def total_matches
        size + @save.size
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
      # need to make this better
      protocol = opts.has_key?(:protocol) ? opts[:protocol] : self.class.protocol
      top = opts.has_key?(:top) ? opts[:top] : false
      begin
        state_class = StateProcessorFactory[state]
      rescue StateProcessorInvalidState
        raise unless block_given?
        state_class = state.class_eval &block
        retry 
      end
      # execute a block if one was passed to us an we are not already defined
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
        raise NameError, "undefined local variable or method `#{m}' for #{self.inspect} (from section method_missing)" 
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
    
    # A convience method for sending the current command to the class of the worker object
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
      return StateProcessorConsume unless arg
      lambda do |a|
        break a == arg ? StateProcessorConsume : StateProcessorNoMatch 
      end
    end
    alias :save_anywhere :_!
    alias :save_anything :_!

    def match_args(matchlist,cmd)
      matches = ArgumentMatches.new 
      
      match_proc = []
      cmd_match = []
      matchlist.each do |m|
        if m.is_a? Proc
          match_proc << m
          cmd_match << StateProcessorFunction
        else
          cmd_match << m
        end
      end

      indifferent_match = lambda do |match,arg|
        if match.is_a?(Symbol) || arg.is_a?(Symbol)
          begin
            return arg if arg.to_sym == match.to_sym 
          rescue NoMethodError 
            return false
          end
        else
          return arg if arg == match
        end
      end

      cmd_match.each_with_index do |arg,i|
        next if cmd_match == StateProcessorFunction
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
            matches << c 
          elsif match_action == StateProcessorConsume
            matches.save << c 
          end
        end
      end
      
      raise NoMatchException unless matches.total_matches >= matchlist.size
      matches 
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
      #
      @previous_command_blocks << @command_block
      @command_block = block 
      
      cmd = @command.dup
      begin 
        matched = match_args(args,cmd)

        with_current = lambda do |&cur_block|
          begin
            (@current_command = @command.shift(matched.total_matches)) if matched.total_matches > 0
            cur_block.call 
          ensure
            @command.unshift *(@current_command)
          end
        end

        raise NoMatchException unless matched
        result = nil # so that we close it, rather than making a bunch of new ones
        if block_given?
          with_current.call do
            raise NoMatchException if @arity_match && block.arity != @command.size
            result = yield *(@command + matched.save)
          end
          set_executed_commands
        else
          # not sure this works the way it ought to
          with_current.call do 
            result = dispatch(self.worker, 
              (@current_command * '_').to_sym, *(@command))
          end
        end
        @result = result.nil? ? @result : result
        stop_with @result if @stop_after
      rescue NoMatchException => e
        # skip that stuff 
      end
      # what are the circumstances where previous doesn't have any?
      @command_block = @previous_command_blocks.pop || @command_block
      @result
    end

    # call context in the worker 
    def context &block
      self.class.worker.context &block  
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
      if block_given?
        @previous_command_blocks << @command_block if @command_block
        @command_block = block
      else
        @command_block = @previous_command_blocks.pop
      end
      set_executed_command_chain
        
      # unwind to the command block 
      throw :pause_processing, result
    end
    alias :answer :pass

    def consume_command! num=1
      @command.shift(num)
    end

    # simple stub implementation error handle.
    # we need to figure out which protocol object called me and pass it back the error
    def error e
      $stderr.puts e 
    end

    def reset_states
      #called by return to clear internal block stack
      callchain.each do |c|
        c.instance_exec do
          # go to the front of the line!
          @command_block = @previous_command_blocks.first || @command_block
          @previous_command_blocks = []
          ps = @previous_states.pop
          @current_state = ps
        end
      end
    end
    private :reset_states

    def set_executed_command_chain
      #return the executed commmands up our call stack
      callchain.each do |c|
        c.instance_eval do 
          set_executed_commands 
        end
      end
    end
    private :set_executed_command_chain

    def set_executed_commands
      (@executed_commands << @current_command.shift) if @current_command
      @current_command = nil
    end 
    private :set_executed_commands
  

    def clean
      reset_states rescue nil
      set_executed_commands rescue nil
    end
    private :clean

    def work
      begin
        unless @current_state 
          @current_state = Fiber.new do |new_cmd|
            @command = new_cmd
            debugger unless @command_block
            loop do
              # this makes the stack unwind to the top of the current command block
              @result = catch :pause_processing do 
                @result = instance_exec(@command,&(@command_block))
              end
              raise StateProcessorDoesNotRespond unless @executed_commands.size > 0
              # resume with the next command
              @command = Fiber.yield @result
            end
          end
        end
        @current_state.resume @command
      rescue FiberError => e
        error "dead fiber"
        @current_state = false
        retry
      rescue LocalJumpError => e
        if e.reason == :return
          reset_states
          set_executed_commands
          #apparently, this will yield to the origin fiber...
          #this feels kinda "black magicky"
          Fiber.yield e.exit_value
        else
          raise e
        end
      rescue StateProcessorDoesNotRespond => e
        reset_states rescue nil
        raise e
      rescue StateProcessorError => e
        clean
        raise e
      rescue StandardError => e
        if methods.include? :report_error then
          report_error e
        else
          error e
        end
        clean
      end
    end
    private :work

    def process cmd, top=true
      @executed_commands = []
      @command = cmd
      
      if top
        @origin = Fiber.new do 
          work
        end
        @result = @origin.resume
      else
        @result = work
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
