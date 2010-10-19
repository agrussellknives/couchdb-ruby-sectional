require 'singleton'
require 'active_support/core_ext'
require 'forwardable'

class ProcessorError < StandardError; end
class ProcessorConflictError < ProcessorError; end
class ProcessorExit < ProcessorError; end
class ProcessorDoesNotRespond < ProcessorError; end
class ProcessorInvalidState < ProcessorError; end

class StateProcessorFactory
  include Singleton

  class StateProcessorList
    def initialize
      @processorlist= {}
    end
    def lookup state, style = false
      raise ArgumentError unless [false,:class].include? style
      if state.class == Symbol or state.class == String then
        (style == :class) ? state.to_s.camelize : state.to_s.underscore.intern  
      elsif state.class == Class then
        (style == :class) ? state.to_s : state.to_s.underscore.split('/').last.intern  
      end
    end

    def knows_state? state

      @processorlist.has_key? lookup(state) ? true : false
    end

    def << state
      @processorlist[lookup(state)] = state
    end
       
    def [] state
      if knows_state? state
        @processorlist[lookup(state)]
      else
        raise ProcessorInvalidState, "No Processor is defined for #{state}"
      end
    end
  end

  @processors= StateProcessorList.new
  self.extend SingletonForwardable
  self.def_delegators :@processors, :lookup, :knows_state, :<<, :[]
    
  class << self

    def create state, protocol, &block
      class_name = @processors.lookup state, :class
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
          rescue ProcessorInvalidState
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
            raise ProcessorDoesNotRespond, ["unknown command","unknown command #{cmd}"]
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
      debugger  
      StateProcessorFactory << k_klass # keep track of everything we create
      k_klass
    end  
  end
end

module StateProcessor
  def self.commands_for key, protocol, &block
    StateProcessorFactory.create key, protocol, &block
  end
end
