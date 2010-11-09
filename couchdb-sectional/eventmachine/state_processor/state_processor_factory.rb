require 'singleton'
require 'active_support/core_ext'
require 'forwardable'
require 'continuation'

module StateProcessor
  class StateProcessorFactory
    include StateProcessorExceptions

    OPTLIST = [:context, :command, :executed_command, :full_command, :origin, :result]  
    
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
            attr_reader :commands
            attr_reader :worker
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
            debugger
            begin
              state_class = StateProcessorFactory[state] 
            rescue StateProcessorInvalidState
              raise unless block_given?
              state = yield
              #StateProcessorFactory.create state, protocol, &block
              retry 
            end
            #TODO investigate whether flatten is appropriate here, or if we should do a single
            # level flatten, or perhaps just leave it to the calling state
            # to prepare our arguments for us.
            @result = state_class.new(self,opts).process(@full_command.flatten,top) 
          end

          def context item=nil
            if block_given?
              yield @context
            elsif item
              @context[item]
            else
              @context
            end
          end

          def method_missing(m, *args, &block)
            puts "method missing called #{m}, #{args}"
            worker = self.class.worker 
            if worker and worker.respond_to? m
              worker.send m, *args, &block
            else
              raise StateProcessorCannotPerformAction.new( 
                  "Could not perform action #{m} in #{self.class} with worker #{worker.class}")
            end 
          end

          # A convience method for sending the current command to the worker object
          def execute *args, &block
            send @command, *args, &block
          end

          def error e
            $stderr.puts e 
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
          
          def otherwise 
            return if @executed_command
            if block_given? 
              yield @command, *(@full_command)
              @executed_command = @command
            else
              debugger
              raise StateProcessorDoesNotRespond, ["unknown command","unknown command #{cmd}"]
            end
          end
          
          def on cmd
            if cmd == @command
              result = yield *(@full_command)
              @executed_command = @command
            end
            @result = result.nil? ? @result : result
          end
         
          def process cmd, top=true 
            @full_command = cmd
            @command = cmd.shift.to_sym
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
            
            # if we are the top process, set ourselves
            # as the continuation for the rest of the
            # commands
            if top
              @result = callcc do |here|
                @origin = here 
                workf.call
              end
            else
              workf.call
            end
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

