module StateProcessor
  module StateProcessorWorker
    include StateProcessor::StateProcessorExceptions

    # Does each Worker call required a block to set the context? by default false
    # but if you need something set each time for the Worker class, it's best to
    # set this to true - setting it to true will cause
    def context_required?
      false unless @context_required
    end

    def context_required= cr
      @context_required = cr
    end

    # Use this method if you want to set context variables for your worker class,
    # ie, variables that need to be set no matter what the command.  These can
    # be based on any criteria available to the scope where context is called.
    def context &block
      raise Argument, "Context requires a block" if not block_given?
      @context = block.binding
      yield
    end

    # You can use this mainly within your <code>run</code> implementation to run
    # commands within the state processor, such as stop_with, or getting information
    # about the current state
    def call_with_context m, *args, &block
      eval "#{m} *#{args}, &block", @context
    end

    def method_missing(m, *args, &block)
      if context_required? and not @context 
        if not block_given? 
          raise StateProcessorNoContext, "Context not set, or could not determine context automatically."
        else
          @context = block.binding
        end
      end
      debugger
      self.run(m,*args, &block)
    end
   
    # This is a method that you <b>must</b> implement in any worker class.  If you don't
    # implement it, your worker class will just raise NotImplementedError for everything.
    def run
      raise NotImplementedError, "You should implement the run method in your own worker class."
    end

  end
end
