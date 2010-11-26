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
    attr_accessor :test
  end

  def simple_match_worker_im_call
    return "simple match worker im call"
  end

  def call_this_in_worker
    return "call this in worker"
  end

  def simple_worker_set_val(arg)
    @a = arg
  end
  
  def simple_worker_get_val
    @a
  end

  protocol RubyPassThroughProtocol

  commands do 
    on_error do |e|
      error e.message
      error e.backtrace
    end

    on :simple_match do
      return true 
    end

    return_after do 
      on :stop_after_this do
        return "stop after this"
      end
      on :stop_after_this do
        return "i should never be seen"
      end

      on :simple_match_worker_im_call
      
      on :simple_worker_get_val
      on :simple_worker_set_val do |a|
        simple_worker_set_val a
      end

      on :call_this_in_worker do
        call_this_in_worker
      end

      on :simple_match_worker_class_call do
        execute :simple_match_worker_class_call 
      end
      
      on :test do |a|
        execute :test=, a
      end
      on :test do
        execute :test
      end

    end

    on :arity_match do |a,b,c|
      return "you shouldn't ever see me"
    end

    on :arity_match do |a,b|
      return "2 params #{a},#{b}"
    end

    on :arity_match do |a|
      return "1 param #{a}"
    end

    on :arity_match do
      return "i should never be run"
    end
    
    on :double_match do
      @hold_this = 1
    end
    on :double_match do
      return 2 + @hold_this
    end

    on :pass_args do |a,b|
      return a*b
    end

    on :arg1 do

      on :arg2 do
        on :arg3 do
          return "arg3"
        end
        on :arg3b do |a|
          return a
        end

        return 'arg2'
      end
      
      on :pass_test4 do
        pass "test4"
      end

      on :pass_test do
        pass "test"
      end

      on :pass_test2 do
        pass "test2"
      end

      on :pass_test3 do
        return "test3"
      end
      puts 'fell off the end'
    end

  end
end

class CommObject
  include RubyPassThroughProtocol
  attr_accessor :state_processor
  def initialize
    @state_processor = StateProcessor[SimpleStateProcessor].new
  end
end

describe SimpleStateProcessor, 'simple matching' do
  co = CommObject.new
  
  describe "factory bits" do
    before do
      @co2 = CommObject.new
    end

    it "should share classes with other state processors" do
      @co2.state_processor.class.should == co.state_processor.class
    end

    it "should new worker instances" do
      @co2.state_processor.worker.should_not == co.state_processor.worker
    end

    it "should remember the worker between calls" do
      worker = co.state_processor.worker 
      co << [:simple_match]
      co.state_processor.worker.should == worker
    end

    it "should be able to modifiy the worker between calls" do
      co << [:simple_worker_set_val,2]
      out = co << [:simple_worker_get_val]
      out.should == 2
    end

    it "class changes should persist between several workers" do
      @co2 << [:test,88]
      out = co << [:test]
      out.should == 88
    end
  end

  it "should raise a exception on invalid messages" do
    lambda { out = co << [:raise_exception] }.should raise_error (
      StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
  end

  it "should do simple arity matching on the blocks" do
    out = co << [:arity_match,1,2]
    out.should == "2 params 1,2"
    out = co << [:arity_match,1]
    out.should == "1 param 1"
  end

  it "should match a simple command" do
    out = co << [:simple_match]
    out.should == true
  end

  it "should stop after one match in a return after block" do
    out = co << [:stop_after_this]
    out.should == "stop after this"
  end

  it "should run an instance_method with no block" do
    out = co << [:simple_match_worker_class_call]
    out.should == 'simple match worker class call'
  end

  it "should look in the worker if an unknown method is called in a block" do
    out = co << [:call_this_in_worker]
    out.should == 'call this in worker'
  end

  it "should call a class method using 'execute'" do
    out = co << [:simple_match_worker_class_call]
    out.should == 'simple match worker class call'
  end

  it "should match more than once without return" do
    debugger
    out = co << [:double_match]
    out.should == 3 
  end
  
  it "should pass arguments into a block" do
    out = co << [:pass_args, 3,4]
    out.should == 12
  end

  it "should accept multi-level matches" do
    out = co << [:arg1,:arg2,:arg3]
    out.should == "arg3"
  end

  it "should fall through multi-level if no matcheds" do
    out = co << [:arg1, :arg2]
    out.should == "arg2"
  end

  it "should accept multi-level matches with arguments" do
    out = co << [:arg1,:arg2,:arg3b,4]
    out.should == 4
  end

  describe "it should be able to pick up where it left off" do

    it "after a call" do
      out = co << [:arg1, :pass_test]
      out.should == "test"

      out = co << [:pass_test2]
      out.should == "test2"
    end

    it "even if it's out of order" do
      out = co << [:pass_test4]
      out.should == "test4"
    end

    it "until it gets a return" do
      out = co << [:pass_test3]
      out.should == "test3"
    end

    it "then it shouldn't anymore" do
      lambda {  out = co << [:arg2] }.should raise_error(
        StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
    end

    it "but it should start over" do
      out = co << [:arg1, :arg2]
      out.should == "arg2"
    end
  end

end
