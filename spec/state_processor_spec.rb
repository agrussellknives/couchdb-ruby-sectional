require_relative '../couchdb-sectional/eventmachine/state_processor'

# got to exist - we'll open it up again later

module RubyPassThroughProtocol
  def <<(cmd)
    @state_processor.process(cmd)
  end

  def error(cmd)
    [:error, cmd]
  end
end

class SimpleStateProcessor
  include StateProcessor
  include StateProcessor::StateProcessorWorker
  
  class << self
    def simple_match_worker_class_call
      return "simple match worker class call" 
    end
  end

  protocol RubyPassThroughProtocol

  commands do 
    on_error do |e|
      debugger 
      error e.mesage
      error e.backtrace
    end

    debugger
    on :simple_match do
      return true 
    end

    on :simple_match_worker_class_call
  end
end

class CommObject
  include RubyPassThroughProtocol
  def initialize
    @state_processor = StateProcessor[SimpleStateProcessor].new
  end
end

describe SimpleStateProcessor, 'simple matching' do
  co = CommObject.new

  it "should match a simple command" do
    out = co << [:simple_match]
    out.should == true
  end

  it "should run a class method with no block" do
    out = co << [:simple_match_worker_class_call]
    out.should == 'simple match worker call'
  end
end
