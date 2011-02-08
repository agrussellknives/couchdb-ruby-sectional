require 'eventmachine'
module StateProcessor
  module StateProcessorSection
    # Generally used to run a compiled function in the context of the worker.  This is useful if you
    # retrieve code or objects from an outside context and need to pass it into the worker
    # for execution.  The worker should implement the "run" method so that it understands
    # the message you send it here.
    # @param [...] args - arguments passed to worker.run
    # @yield [...] results - the return value of worker.run
    def run *args, &block
      @current_command.map do |c|
        args.unshift c.to_sym
      end
      self.worker.run(*args, &block)
    end
    
    # Sends a command to the class of the worker object - affecting all worker objects
    # in all sessions.  Are you SURE?
    #
    # @param [Symbol] cmd - the name of the class method to execute
    # @param args - arguments passed to that method
    # @yield - If given a block it executes that block in by running it under "instance_eval
    #   on the worksers class.
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


    # Sends a command to a different component, optionally continuing to execute the current
    # processor.
    #
    # Deferred messages may execute the yield block at after the current StateProcessor has
    # already exited, so you should not rely on that data being available to calling context
    # 
    # @param [StateProcessor] state
    # @param [Array] msg
    # @param [Hash] opts
    # @options :deferred = false
    # @options :protocol = self.class.protocol
    # @yield If given a block it will yield the return value of the message to it
    def send state, msg, opts = {}, &block
      options = {:deferred => false,
                 :protocol => self.class.protocol }.merge opts
      
      # raises InvalidState if the state hasn't been 
      # created yet
      state_class = StateProcessorFactory[state]
      state_class.protocol = options[:protocol] 
      processor = processor_for(state_class,opts)
      if options[:deferred] then
        # raise ArgumentError, "A block is required for deferred sends" unless block_given?
        raise StateProcessorError, "Not able to defer because there is no event loop running." unless EM.reactor_running?
        callback = block if block_given?
        op = lambda { processor.process(msg,true) }
        EventMachine.defer op, callback
        true 
      else
        res = processor.process(msg,true)
        if block_given?
          yield res
        else
          return res
        end
      end
    end
     
    # Called in the context of the worker before each message is passed to it.
    # You normally use this to tell the worker something you wouldn't normally
    # know about the state that it was called from
    def context &block
      debugger
      self.worker.context(&block)  
    end

    # Raises StateProcessorExit, allowing cleanup but not returning anything.
    # @raises [StateProcessorExit]
    def exit e
      raise StateProcessorExit, e
    end
 
    # Create a LocalJumpError exactly like return.  You should generally use
    # 'return' instead, although this should be equivalent
    def stop_with result
      e = LocalJumpError.new
      #subvert! cheat! 
      e.instance_eval do
        @reason = :return
        @exit_value = result
      end
      raise e 
    end
   
    # Within the given block, any "on" blocks are only executed if they have
    # matching parameters and the number of arguments supplied to the block
    # is equal to the number of parts left in the message.
    # @alias matching_arity
    def arity_match
      begin 
        @arity_match = true
        yield
      ensure
        @arity_match = false
      end
    end
    alias :matching_arity :arity_match
      
    # Within the given block, any "on" blocks that are executed will have an implicit
    # return after  their last statement.  Without this, after an "on" block is executed
    # the processor will continue to look for other matches.
    # @alias stopping_after
    def return_after 
      begin
        @stop_after = true
        yield
      ensure
        @stop_after = false
      end
    end
    alias :stopping_after :return_after

    # Answer the message with "result" but do not reset the processor.  Message processing
    # will resume on the current command block, or the block supplied to "answer"
    # @param result - the result to pass to the the protocol.
    # @yields the message the protocol responds with
    # @alias pass
    def answer result, &block
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
      pause = PauseProcessing.new
      pause.value = result
      raise pause
    end
    alias :pass :answer

    # Remove "num" commands from the beginning of the message.
    # @returns the removed command(s)
    # @param [Fixnum] num, the number of commands to remove (default 1)
    def consume_command! num=1
      @command.shift(num)
    end

    # simple stub implementation error handle.
    # we need to figure out which protocol object called me and pass it back the error
    def error e
      if self.class.protocol.respond_to? :error
        self.class.protocol.error e
      else
        $stderr.puts e
      end
    end
  end
end




