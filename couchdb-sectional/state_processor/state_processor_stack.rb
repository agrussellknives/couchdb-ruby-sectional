module StateProcessor
  module StateProcessorSection

    # Call stack and state managment

    private 
    # Provides an Enumerator of each of the calling states of the current processor
    # @return [Enumerator] an enumerator that yields each calling state
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

    # Provides an Enumerator of each of the "origin" points for each calling state
    # enables you to jump anywhere back up the processor stack
    # @return [Enumerator] an enumerator which points to the "origin" fiber for each calling state
    def originchain
      Enumerator.new do |y|
        callchain.each do |cs|
          y.yield cs.origin if cs.origin
        end
      end
    end

    # Clears calling state information all the way up the processor stack, removing any stored
    # command blocks and allow the current fiber to expire
    def reset_states
      #called by return to clear internal block stack
      callchain.each do |c|
        c.instance_exec do
          # go to the front of the line!
          @command_block = @previous_command_blocks.first || @command_block
          @previous_command_blocks = []
          @current_state = nil
        end
      end
      nil
    end

    # Copies the currently executed command back up the processor stack, enabling parent
    # processors to see what the current state of command processing is.
    def set_executed_command_chain
      #return the executed commmands up our call stack
      callchain.each do |c|
        c.instance_eval do 
          set_executed_commands 
        end
      end
      nil
    end

    # Sets the executed commands to the current match, and clears the current command
    def set_executed_commands
      (@executed_commands << @current_command.shift) if @current_command
      @current_command = nil
      nil
    end 

    # Resets all states, sets the executed commands to whatever the last execution was
    # and supresses any error encountered while doing so.  Basically, this reset's the
    # processor tree in the event of an unrecoverable error
    def clean
      reset_states rescue nil
      set_executed_commands rescue nil
    end
  end
end
