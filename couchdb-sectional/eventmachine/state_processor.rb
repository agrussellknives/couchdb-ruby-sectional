require 'singleton'
require 'active_support'


class ProcessorError < StandardError; end
class ProcessorConflictError < ProcessorError; end
class ProcessorExit < ProcessorError; end
class ProcessorDoesNotRespond < ProcessorError; end


class StateProcessorFactory
  include Singleton
  class << self
    @stateprocessors = []
    def stateprocessors state
      index = @stateprocessors.index(state)
      @stateprocessors[index]
    end
    def statetoclass state
      state.to_s.camelize
    end
    def create state, protocol, &block
      class_name = statetoclass state 
      unless const_defined? class_name.to_sym
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
                state_class = const_get(StateProcessorFactory.statetoclass(state))
              rescue NameError => e
                raise ProcessorInvalidState, 
                  "No processor defined for #{StateProcessorFactory.statetoclass(state).to_s}"
              end
              context = {}
              context = yield context, @full_command if block_given?
              StateProcessorFactory.stateprocessors(state_class).new(context).process(@full_command)
            end

            def error e
              $stderr.puts e 
            end

            def exit e
              raise ProcessorExit, e
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
                raise ProcessorDoesNotRespond, ["unknown command","unkknown command #{cmd}"]
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
              rescue ProcessorError => e
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
          k_klass = const_get(class_name.to_sym) # get the class 
          StateProcessorFactory.stateprocessors << k_klass # keep track of everything we create
          k_klass
      else
        raise ProcessorConflictError, "You cannot create two Processors for the same state in a single process."
      end
    end  
  end
end
