require 'singleton'
require 'active_support'


class ProcessorError < StandardError; end
class ProcessorConflictError < ProcessorError; end
class ProcessorExit < ProcessorError; end
class ProcessorDoesNotRespond < ProcessorError; end

class ProcessorDelegatesTo < ProcessorError 
  attr_reader :state
  def initialize state
    @state = state
  end
end

class StateProcessorFactory
  include Singleton
  class << self
    def create state, protocol, &block
      class_name = state.to_s.camelize
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
            def initialize
              @command = nil
              @executed_command = nil
            end
            def switch_state state
              raise ProcessorDelegatesTo, state 
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
            def otherwise 
              if block_given?
                yield @command
                @executed_command = @command
              end
            end
            def on cmd
              if cmd == @command
                yield @command
                @executed_command = @command
              end
            end
            def process cmd 
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
            
              if @executed_command == nil
                self.otherwise
                cmd = @command
                @command = nil
                raise ProcessorDoesNotRespond, ["unknown_command","unknown command #{cmd}"]
              end

            end
            def inspect
               "#<#{self.class}:#{self.object_id << 1} protocol: #{self.class.protocol}>"
            end
          end
          const_set(class_name.to_sym,klass) 
          const_get(class_name.to_sym) # return the class
      else
        raise ProcessorConflictError, "You cannot create two Processors for the same state in a single process."
      end
    end  
  end
end
