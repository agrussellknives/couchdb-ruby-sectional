#include state processor stuff

require_relative "state_processor/state_processor_exceptions"
require_relative "state_processor/state_processor_list"
require_relative "state_processor/state_processor_factory"
require_relative "state_processor/state_processor_worker"

module StateProcessor

  extend self

  def commands_for key, protocol, &block
    if block_given? then
      StateProcessorFactory.create key, protocol, &block
    else
      StateProcessorFactory.create key, protocol do |command|
        puts command
      end
    end
  end

end
