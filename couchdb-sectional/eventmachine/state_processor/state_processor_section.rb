module StateProcessor
  module StateProcessorSection
    include StateProcessor::StateProcessorExceptions
    include StateProcessor::StateProcessorMatchConstant
    extend ActiveSupport::Concern  
   
    class NoMatchException < StandardError; end

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
    
    OPTLIST = [ :command, :executed_command, :origin, :result, :callingstate, :current_command ]

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
      @previous_continuations = []
      @processors = {}
      @command_block = self.class.commands
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

    # dispatches called methods to the class of the current worker object
    # this needs a better implementation
    def method_missing(m, *args, &block)
      if self.class.worker.respond_to? m 
        dispatch(self.class.worker, m, *args, &block)
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
      self.class.worker.new.run *args, &block         
    end
    
    # A convience method for sending the current command to an instance of the worker object
    def execute cmd=nil, *args, &block
      if block_given?
        # i can't think of a reason why you'd need to pass args in if you gave
        # it a block
        dispatch(self.class.worker.new.instance_eval(&block))
      else
        ex = ArgumentError.new('Execute must be passed a method name or block')
        raise ex unless cmd.kind_of? Symbol
        begin 
          dispatch(self.class.worker.new, cmd, *args)
        rescue StateProcessorCannotPerformAction => e
          # the generic exception is better in this instance
          raise ex
        end
      end
    end

     
    def _(arg=nil)
      return STATE_PROCESSOR_MATCH unless arg
      lambda do |a| 
        break a == arg ? STATE_PROCESSOR_MATCH : STATE_PROCESSOR_NOMATCH 
      end
    end

    def _!(arg=nil)
      return STATE_PROCESSOR_MATCH unless arg
      lambda do |a|
        break a == arg ? STATE_PROCESSOR_CONSUME : STATE_PROCESSOR_NOMATCH 
      end
    end

    def match_args(args,cmd)
      matches = []
      nomatch_ex = NoMatchException.new
      cmd.each_with_index do |i,arg|
        if args[i] == STATE_PROCESSOR_MATCH 
          matches << arg
        elsif arg != arg[i]
          raise nomatchex
        else 
          match = args[i][arg] rescue nil 
          if match == STATE_PROCESSOR_MATCH 
            matches << arg
          elsif match == STATE_PROCESSOR_CONSUME
            matches << nil
          end
        end
      end
    end

    def on *args, &block
      #TODO, rewrite so it stores commands and does a lookup at runtime rather than
      #running through all of the commands
      # this is O(N) since it calls this method once for each "on" block.
      # I could get it instead to store them in a lut, and then executed based
      # on the value of "matched" which would be better
      
      debugger 
      match_args(args,@command.dup)
       
      if block_given?
        #TODO - implement arity checking.
        (@current_command = @command.shift(matched.size)) if matched.size > 0
        puts @current_command
        result = yield *(cmd)
        @command.unshift(@current_command)
        @executed_commands = @current_command.dup
        @current_command = nil
      else
        # not sure this works the way it ought to
        result = dispatch(self.class.worker, matched.shift, *matched)
      end
      @result = result.nil? ? @result : result
      stop_with @result if @stop_after
      
      # the rescue has the effect of ignoring the method body if there
      # were no argument matches
      rescue NoMatchException
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

    def resume_here
    end

    def return_after 
      @stop_after = true
      yield
      @stop_after = false
    end
    alias :stopping_after :return_after

    def pass result, &block
      # reset the contiuation on the call chain, so the next 
      # "process" call will invoke our own contiuation
      # if a block is given we set the contiuation to
      # execute that block
      #
      #if block_given?
      #  # i need to store the previous command block so i can
      #  @result = callcc { |cc| @pass_continuation = cc } 
      #  instance_exec(@command,block)
      #end
      
      callchain.each do |c|
        c.instance_exec @pass_continuation do |cc|
          @previous_continuations << @pass_continuation
          @pass_continuation = cc
        end
      end
      stop_with result
    end

    def reset_continuations
      callchain.each do |c|
        c.instance_exec do |cc|
          pc = @previous_continuations.pop
          @pass_continuation = pc
        end
      end
    end

    def consume_command! num=1
      puts 'command consumed'
      @command.shift(num)
    end

    # simple stub implementation error handle.
    def error e
      $stderr.puts e 
    end

    def process cmd, top=true
      puts self.inspect 
      @command = cmd
      @pass_continuation.call if @pass_continuation
      # define the main working block
      workf = lambda do 
        begin
          @result = callcc { |cc| @pass_continuation = cc }
          # -- CALLING OUR OWN PASS CONTIUATION WILL JUMP TO HERE --#
          # it should NOT be possible to reset the TOP between calls. #
          instance_exec(@command,&(@command_block))
        rescue LocalJumpError => e
          if e.reason == :return 
            reset_continuations 
            @origin.call e.exit_value
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
        rescue e
          puts 'rescued everything!'
        end
      end
      
      # if we are the top section, set ourselves
      # as the continuation for the rest of our sub-states
      # i wonder if throw catch would be easier to understand here.
      if top
        @result = callcc do |here|
          @origin = here 
          workf.call
        end
      else
        workf.call
      end
      #-- CALLING THE ORIGIN CONTIUATION WILL COME BACK TO HERE --#
      @result
    end
   
    def inspect
       hex_id = "%x" % self.object_id << 1
       "#<#{self.class.worker.to_s}Processor:0x#{hex_id} protocol: #{self.class.protocol}>"
    end
  end
end
