
module RubyPassThroughProtocol
  def <<(cmd)
    @state_processor.process(cmd)
  end

  def error(cmd)
    [:error, cmd]
  end
end

class CommObject
  include RubyPassThroughProtocol
  attr_accessor :state_processor
  def initialize stp 
    @state_processor = StateProcessor[stp].new
  end
end
