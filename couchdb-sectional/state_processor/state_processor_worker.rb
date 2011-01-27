require 'active_support/concern'

module StateProcessor
  module StateProcessorWorker
    include StateProcessor::StateProcessorExceptions
    extend ActiveSupport::Concern

    module ClassMethods
      # Use this method if you want to set context variables for your worker class,
      # ie, variables that need to be set no matter what the command.  These can
      # be based on any criteria available to the scope where context is called.
      # You normall use this to tell the worker something it wouldn't know about the
      # state it was called from.
      def context &block
        return @context if not block_given?
        @context = block
      end
       
      def <<(*args)
        debugger
        puts args
      end
    end
    
    def initialize
      self.class.nesting.each do |nest|
        cont = nest.context
        instance_eval &cont if cont
      end
    end

    # you can use this within "execute" or the "run" implementation to
    # call methods or look for variables in the scope of
    def call_with_context m, *args, &block
      eval "#{m} *#{args}, &block", self.class.context.binding
    end

    def method_missing(m, *args, &block)
      self.run(m,*args, &block)
    end
   
    # This is a method that you should generally implement in any worker class.  
    # It is used to implement arbitrary callbacks in the context of the worker class
    def run *args
      puts args
      raise NotImplementedError, "You should implement the run method in your own worker class."
    end

  end
end
