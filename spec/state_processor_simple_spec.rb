require_relative '../couchdb-sectional/eventmachine/state_processor'

require_relative 'helpers'


class SimpleStateProcessor
  include StateProcessor
  include StateProcessor::StateProcessorWorker
  
  class << self
    def simple_match_worker_class_call
      return "simple match worker class call" 
    end
    attr_accessor :artest
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

  def infers_method_name
    return "ok"
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

    on :should, :not, :match, :more_specific do
      return "shouldn't see this!"
    end

    on :should, :not do |m|
      return m
    end

    on :stop_after_this do
      return "stop after this"
    end
    on :stop_after_this do
      return "i should never be seen"
    end

    on :error_test do
      bibbity_bobbety_boo
    end

    on :error_test2

    return_after do 
      on :simple_match_worker_im_call
     
     on :infers, :method, :name
      
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
     
      matching_arity do
        on :test do |a|
          execute :artest=, a
        end
        on :test do
          execute :artest
        end
      end

    end

    matching_arity do
      return_after do
        on :arity_match do |a,b,c|
          "you shouldn't ever see me"
        end

        on :arity_match do |a,b|
          "2 params #{a},#{b}"
        end

        on :arity_match do |a|
          "1 param #{a}"
        end

        on :arity_match do
          "i should never be run"
        end
      end
    end

    on :arity_no_match do
      return "arity no match"
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
        on :arg4 do |a|
          return a
        end

        return 'arg2'
      end
      
      
      on :pass_test5 do
        pass "test5" do
          on :pass_test5_2 do
            return "ok"
          end
        end
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


describe SimpleStateProcessor, 'simple matching' do
  before do
    @co = CommObject.new SimpleStateProcessor
  end
  
  describe "factory bits" do
    before do
      @co2 = CommObject.new SimpleStateProcessor
    end

    it "should share classes with other state processors" do
      @co2.state_processor.class.should == @co.state_processor.class
    end

    it "should new worker instances" do
      @co2.state_processor.worker.should_not == @co.state_processor.worker
    end

    it "should remember the worker between calls" do
      worker = @co.state_processor.worker 
      @co << [:simple_match]
      @co.state_processor.worker.should == worker
    end

    it "should be able to modifiy the worker between calls" do
      @co << [:simple_worker_set_val,2]
      out = @co << [:simple_worker_get_val]
      out.should == 2
    end

    it "class changes should persist between several workers" do
      @co2 << [:test,88]
      out = @co << [:test]
      out.should == 88
    end
  end

  describe "should recover from errors gracefully" do
    it "if it doesn't respond at all it raises an error" do
      lambda { @co << [:boogety] }.should raise_error (
        StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
      out = @co << [:simple_match]
      out.should == true
    end

    it "errors within worker code are consumed" do
      @co << [:error_test]
      out = @co << [:simple_match]
      out.should == true
    end

    it "trying to execute worker code that doesn't exist is an error" do
      lambda { @co << [:error_test2]}.should raise_error (
        StateProcessor::StateProcessorExceptions::StateProcessorCannotPerformAction)
      out = @co << [:simple_match]
      out.should == true
    end

  end

  it "should raise a exception on invalid messages" do
    lambda { out = @co << [:raise_exception] }.should raise_error (
      StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
  end

  it "should do simple arity matching on blocks in an arity match block" do
    out = @co << [:arity_match,1,2]
    out.should == "2 params 1,2"
    out = @co << [:arity_match,1]
    out.should == "1 param 1"
  end

  it "should not do arity matching on other blocks" do
    out = @co << [:arity_no_match,1,2]
    out.should == "arity no match"
  end

  describe "guard clauses" do
    it "should match a simple command" do
      out = @co << [:simple_match]
      out.should == true
    end

    it "shouldn't match more specific guards" do
      out = @co << [:should, :not, :match, :anything]     
      out.should == :match
    end

    it "should match less specific guards" do
      out = @co << [:should, :not, :match]
      out.should == :match
    end
  end

  it "should stop after one match in a return after block" do
    out = @co << [:stop_after_this]
    out.should == "stop after this"
  end

  it "should run an instance_method with no block" do
    out = @co << [:simple_match_worker_class_call]
    out.should == 'simple match worker class call'
  end

  it "should infer the instance method name" do
    out = @co << [:infers,:method,:name]
    out.should == 'ok'
  end

  it "should look in the worker if an unknown method is called in a block" do
    out = @co << [:call_this_in_worker]
    out.should == 'call this in worker'
  end

  it "should call a class method using 'execute'" do
    out = @co << [:simple_match_worker_class_call]
    out.should == 'simple match worker class call'
  end

  it "should match more than once without return" do
    out = @co << [:double_match]
    out.should == 3 
  end

  it "should pass arguments into a block" do
    out = @co << [:pass_args, 3,4]
    out.should == 12
  end

  it "should accept multi-level matches" do
    out = @co << [:arg1,:arg2,:arg3]
    out.should == "arg3"
  end

  it "should fall through multi-level if no matcheds" do
    out = @co << [:arg1, :arg2]
    out.should == "arg2"
  end

  it "should accept multi-level matches with arguments" do
    out = @co << [:arg1,:arg2,:arg4,4]
    out.should == 4
  end

  describe "it should be able to pick up where it left off" do

    it "after a call" do
      out = @co << [:arg1, :pass_test]
      out.should == "test"

      out = @co << [:pass_test2]
      out.should == "test2"
    end

    it "even if it's out of order" do
      out = @co << [:arg1, :pass_test]
      out = @co << [:pass_test2]
      out = @co << [:pass_test4]
      out.should == "test4"
    end

    it "executing the pass functions block" do
      out = @co << [:arg1,:pass_test5]
      out.should == "test5"
      out = @co << [:pass_test5_2]
      out.should == "ok"
    end

    it "until it gets a return" do
      out = @co << [:arg1, :pass_test]
      out.should == "test"
      out = @co << [:pass_test3]
      out.should == "test3"
    end

    it "then it shouldn't anymore" do
      lambda {  out = @co << [:arg2] }.should raise_error(
        StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
    end

    it "but it should start over" do
      out = @co << [:arg1, :arg2]
      out.should == "arg2"
    end
  end

end
