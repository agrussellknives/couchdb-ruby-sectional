require 'singleton'
require 'active_support/core_ext'
require 'forwardable'


class StateProcessorFactory
  include StateProcessorExceptions

  @processors = StateProcessorList.new()
  class << self
    attr_accessor :processors
  end

  self.extend SingleForwardable
  self.def_delegators :processors, :lookup, :knows_state?, :<<, :[] 

  class << self

    def create state, protocol, &block
      class_name = lookup state, :class
      klass = Class.new(Object) do
        @state = state
        @protocol = protocol
        @commands = block
        class << self
          attr_accessor :protocol
          attr_accessor :state
          attr_reader :commands
        end

        attr_accessor :command
        attr_accessor :full_command

        def initialize context = nil
          @context = context 
          @command = nil
          @executed_command = nil
          @full_command = nil
        end

        def switch_state state
          begin
            state_class = StateProcessorFactory[state]
          rescue StateProcessorInvalidState
            if block_given? then
              context = {}
              context = yield context, @full_command
              StateProcessorFactory[state_class].new(context).process(@full_command)
            else
              raise
            end
          end
        end

        def error e
          $stderr.puts e 
        end

        def exit e
          raise StateProcessorExit, e
        end
       
        def on_error error=nil
          self.define_method :report_error, error, &block
        end
        
        def otherwise cmd 
          return if @executed_command
          if block_given? 
            yield *(@full_command)
            @executed_command = @command
          else
            raise StateProcessorDoesNotRespond, ["unknown command","unknown command #{cmd}"]
          end
        end
        
        def on cmd
          if cmd == @command
            yield *(@full_command)
            debugger
            @executed_command = @command
          end
        end
       
        def process cmd
          @full_command = cmd
          @command = cmd.shift.to_sym
          begin
            instance_exec(command,&(self.class.commands))
          rescue LocalJumpError => e
            return e.exit_value if e.reason == :return
          rescue StateProcessorError => e
            raise e
          rescue StandardError => e
            if methods.include? :report_error then
              report_error e
            else
              error e
            end
          end
        end
        
        def inspect
           "#<#{self.class}:#{self.object_id << 1} protocol: #{self.class.protocol}>"
        end
      end

      const_set(class_name.to_sym,klass)
      StateProcessorFactory << klass # keep track of everything we create
   
   end  
  end
end


