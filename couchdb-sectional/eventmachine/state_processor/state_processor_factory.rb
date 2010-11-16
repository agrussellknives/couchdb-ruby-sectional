require 'active_support/core_ext'
require 'forwardable'
require 'continuation'
require 'fiber'

module StateProcessor
  class StateProcessorFactory
    include StateProcessorExceptions

    OPTLIST = [ :command, :executed_command, :origin, :result]  
    
    @processors = StateProcessorList.new()
    class << self
      attr_accessor :processors
    end

    self.extend SingleForwardable
    self.def_delegators :processors, :lookup, :knows_state?, :add_state, :[] 

    class << self

      def create state, protocol, worker, create_options = {}, &block
        class_name = lookup state, :class
        klass = Class.new(Object) do
          
          #valid creation_options
          include StateProcessorExceptions
          @state = state
          @protocol = protocol
          @commands = block
          @worker = worker
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

          OPTLIST.collect { |opt| attr_accessor opt }
          
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

          def initialize callingstate=nil, opts = {}
            # who knew - you can't call an attr_accessor from initialize
            self.options = callingstate.options.merge opts if callingstate
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
            @result = state_class.new(self,opts).process(@command.flatten,top) 
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

          def on *args, &block
            #TODO, rewrite so it stores commands and does a lookup at runtime rather than
            #running through all of the commands
            # this is O(N) since it calls this method once for each "on" block.
            # I could get it instead to store them in a lut, and then executed based
            # on the value of "matched" which would be better
            cmd = @command.dup
            # i want it to match only in order, so we take_while instead of a intersection
            matched = args.take_while do |arg|
              arg == cmd.shift.to_sym
            end
            if matched == args 
              # should I do an arity check here?
              if block_given?
                @current_command = @command.shift(matched.size)
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
            end
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

          def exit e
            raise StateProcessorExit, e
          end
         
          def on_error error=nil, &block
            self.class.send :define_method, :report_error, &block
          end

          def stop_with result
            @origin.call result 
          end

          def resume_here
          end

          def stop_after
            @stop_after = true
            yield
            @stop_after = false
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
            
                # define the main working block
                workf = lambda do 
                  begin
                    instance_exec(command,&(self.class.commands))
                  rescue LocalJumpError => e
                    return e.exit_value if e.reason == :return
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
        StateProcessorFactory.add_state klass, class_name.underscore.intern 
        class_name.underscore.intern
      end  
    end
  end
end

