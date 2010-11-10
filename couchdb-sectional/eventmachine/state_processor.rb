require 'active_support/concern'

#include state processor stuff

require_relative "state_processor/state_processor_exceptions"
require_relative "state_processor/state_processor_list"
require_relative "state_processor/state_processor_factory"
require_relative "state_processor/state_processor_worker"

#TODO - fix this to require all protocols dynamically
require_relative "nil_protocol"
require_relative "query_server_protocol"

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

  module ClassMethods
    def protocol(proto = nil)
      if proto then
        @protocol = proto
      else
        unless @protocol 
          #the first one is always ourselves, so skip it.
          @protocol = nesting[1..-1].each do |cl|
             protocol = cl.protocol
             # cause that's how i roll.
             break protocol if protocol 
          end || NilProtocol
        end
        @protocol
      end
    end
   
    def key(key=nil)
      @key = key ? key : @key
    end
    
    def worker(worker = nil)
      @worker = worker ? worker : @worker
    end

    def test
      'test'
    end

    def commands options={}, &block
      opts = {
        :key => self.to_s.underscore.to_sym,
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

end
