require 'uuidtools'

require_relative './state_processor_argument_matching'
require_relative './state_processor_stack'
require_relative './state_processor_commands'

module StateProcessor
  module StateProcessorSection
    include StateProcessor::StateProcessorExceptions
    include StateProcessor::StateProcessorMatchConstant
    
    extend ActiveSupport::Concern  
  
    # Similar to LocalJumpError - used when we want to "answer" a message.
    class PauseProcessing < StandardError
      attr_accessor :value
    end
    AnswerToken = class.new(BasicObject)
            
        
    OPTLIST = [ :command, :executed_command, :origin, :result, :callingstate, :current_command, :worker ]
    INHERITED_OPTS = [ :command, :executed_command, :result, :current_command]
    
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

    def inheritable_options_from
      INHERITED_OPTS.inject({}) do |memo,k|
        memo[k] = self.send "#{k}"
        memo
      end
    end

    def initialize callingstate=nil, opts = {}
      # who knew - you can't call an attr_accessor from initialize
      self.options = callingstate.inheritable_options_from.merge opts if callingstate
      @callingstate = callingstate
      @previous_states = []
      @processors = {}
      @command_block = self.class.command_block
      @previous_command_blocks = []
      @worker = self.class.worker.new
      self
    end

    # Process the message from here using a different compoenent. This can be an external
    # component (in which case it should already be defined) or a nested component,
    # in which case the command block should be definied within the block
    # passed to switch_state
    # @param [StateProcessorSection] state - use the processor for this state.
    # @param [Hash] opts - options for the state
    # @options opts :protocol - switch the protocol for RESPONDING to the 
    #   message.  The receiving protocol cannot be changed once the message is received.
    # @options opts :top - set this to 'true' to set this state as the "top" state.
    #   'returns' within this state will exit at the end of the switch state block
    # @yield - a block must be supplied if the state does not already exist.  It will
    #   be class_evaled in order to set up the processor
    def switch_state state, opts = {}, &block
      # need to make this better
      protocol = opts.has_key?(:protocol) ? opts[:protocol] : self.class.protocol
      top = opts.has_key?(:top) ? opts[:top] : false
      begin
        state_class = StateProcessorFactory[state]
      rescue StateProcessorInvalidState
        raise unless block_given?
        state_class = state.class_eval(&block)
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
        obj.__send__ m, *args, &block
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
        
    # Match the message, executing the block if the message is matched.
    # @param [Symbol, Regex, Proc, Object, Array,...] - an object ot match.  If it is equal
    #  then it is considered to have "matched" the argument.
    # @yield remaining parts of the message
    # @todo Refactor so it uses a LUT with multiple matchprocs, instead of calling this
    # method each time it is encountered.
    def on *args, &block
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
            @command.unshift(*@current_command)
          end
        end

        raise NoMatchException unless matched
        result = nil # so that we close it, rather than making a bunch of new ones
        if block_given?
          with_current.call do
            raise NoMatchException if @arity_match && block.arity != @command.size
            result = yield(*(@command + matched.save))
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

    def work
      begin
        unless @current_state 
          @current_state = Fiber.new do |new_cmd|
            @command = new_cmd
            loop do
              # this makes the stack unwind to the top of the current command block
              # when you resume the current state fiber, this is where it starts again.
              # it actually runs all the way down to the end of this loop 
              # and then comes back.
              result = nil
              # redefine the command block to keep our constant
              # lookup predictable
              begin
                result = instance_eval &@command_block 
                raise StateProcessorDoesNotRespond unless @executed_commands.size > 0
              rescue PauseProcessing => e
                if
                @command = originchain.first.transfer e.value 
              rescue LocalJumpError => e
                if e.reason == :return
                  reset_states
                  set_executed_commands
                  originchain.first.transfer e.exit_value
                else
                  raise e
                end
              rescue StateProcessorDoesNotRespond => e
                reset_states rescue nil
                raise e
              rescue StateProcessorError => e
                clean
                raise  
              rescue StandardError => e
                # need to get this into the protocol
                rep = callchain.each.find do |cs|
                  cs.worker.respond_to? :report_error
                end
                raise e unless rep
                debugger
                self.instance_exec e, &rep.worker.report_error
                clean
                @command = Fiber.yield result
              else
                @command = Fiber.yield result
              end
            end
          end
        end
        result = @current_state.transfer @command
      rescue FiberError => e
        error "this really should happen. a fiber had a problem -> #{e}"
        @current_state = false
        retry
      end
    end
    private :work

    # Called by the protocol to set up the origin fiber and pass control
    # to the proper fiber as necessary
    def process cmd, top=true
      @executed_commands = []
      @command = cmd
      
      if top
        @origin = Fiber.new do
          result = work
          Fiber.yield result
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
