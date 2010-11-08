#include state processor stuff

require_relative "state_processor/state_processor_exceptions"
require_relative "state_processor/state_processor_list"
require_relative "state_processor/state_processor_factory"
require_relative "state_processor/state_processor_worker"

#TODO - fix this to require all protocols dynamically
require_relative "nil_protocol"
require_relative "query_server_protocol"

class StateProcessor

  class << self
    def protocol(protocol=nil) 
      @protocol = protocol ? protocol : @protocol  
    end
   
    def key(key=nil)
      @key = key ? key : @key
    end
    
    def worker(worker = nil)
      @worker = worker ? worker : @worker
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
