require 'active_support/concern'
require 'active_support/core_ext'

#include state processor stuff

require_relative "state_processor/state_processor_exceptions"
require_relative "state_processor/state_processor_list"
require_relative "state_processor/state_processor_factory"
require_relative "state_processor/state_processor_worker"
require_relative "state_processor/state_processor_section"

#TODO - fix this to require all protocols dynamically
require_relative "state_processor/protocols/nil_protocol"
require_relative "state_processor/protocols/query_server_protocol"

module ClassNesting
  # this cannot be the best way to do this
  # start one up the nesting chain, and see if any of
  # our outer classes have the method we're looking for.
  # seriously, this feels pretty wrong...
  def nesting
    nesteds = self.to_s.split('::')
    res = []
    nesteds.reverse_each do |o| 
      res << nesteds.join('::').constantize
      nesteds.pop
    end
    res
  end
end

class Class
  include ClassNesting
end

module StateProcessor
  extend ActiveSupport::Concern

  def self.[](arg)
    StateProcessorFactory[arg]
  end

  def self.all
    StateProcessorFactory.processors
  end

  module ClassMethods
    def protocol(proto = nil)
      if proto then
        @protocol = proto
      else
        unless @protocol 
          #the first one is always ourselves, so skip it.
          # subvert the intened use of each_with_object
          @protocol = nesting[1..-1].each_with_object(nil) do |cl|
             protocol = cl.protocol
             # cause that's how i roll.
             break protocol if protocol 
          end
        end
        @protocol
      end
    end
        
    def on_error error=nil, &block
      # save the block and execute as a method
      define_method :report_error, block 
    end

    def key(key=nil)
      if key then
        @key = key
      else
        unless @key
          @key = self.to_s.underscore.to_sym
        end
        @key
      end
    end

    #def const_missing const
    #  debugger
    #  puts "const missing form stateprocess module #{const}"
    #end

    def processor
      StateProcessorFactory[key]
    end
    
    def worker(worker = nil)
      @worker = worker ? worker : @worker
    end

    def commands options={}, &block
      if StateProcessorFactory.knows_state? self
        raise StateProcessorCommandsAlreadyDefined, "command block already defined for #{self}"
      end

      opts = {
        :key => key, 
        :protocol => protocol 
      }.merge options
      
      if block_given? then
        StateProcessorFactory.create( opts[:key], opts[:protocol], self, &block)
      else
        StateProcessorFactory.create( opts[:key], opts[:protocol], self) do |command|
          puts command
        end
      end
    end
  end

  included do |name|
    name_sym = name.to_s.split('::').last
    silence_warnings do
      self.nesting.last.const_set(name_sym,name)
    end
  end
end
