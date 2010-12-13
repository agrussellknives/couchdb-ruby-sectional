require 'active_support/core_ext'
require 'forwardable'
require 'continuation'
require 'fiber'

require_relative './state_processor_section'

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
          include StateProcessor::StateProcessorSection
          include StateProcessorExceptions
          
          @state = state
          @protocol = protocol
          @worker = worker
          @command_block = block
          
         class << self
           attr_accessor :protocol
           attr_accessor :state
           attr_accessor :worker
           attr_accessor :command_block

           def inspect
             hex_id = "%x" % self.object_id << 1
             "#<#{self.worker.to_s}ProcessorClass:0x#{hex_id} protocol: #{self.protocol}>" 
           end

           def const_missing const
             puts "constant missing #{const}"
             debugger;1
           end
         end
       end
        StateProcessorFactory.add_state klass, class_name.underscore.intern 
        class_name.underscore.intern
      end  
    end
  end
end

