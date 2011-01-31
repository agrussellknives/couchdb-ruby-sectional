require_relative 'helpers'

class ErrorHandler
  include StateProcessor
  include StateProcessorWorker

  class RecoverableError < StateProcessorRecoverableError; end

  protocol RubyPassThroughProtocol

  on_error do |e|
    return "got an error #{e}"
  end

  commands do 
    on :is_alive do
      return true
    end

    on :fatal_error do
      raise SecurityError
    end

    on :not_so_fatal_error do
      raise StandardError
    end

    on :not_fatal_at_all_error do
      raise RecoverableError
    end
  end
end

describe "should handle errors" do
  
  before :each do
    @eco = EventedCommObject.new ErrorHandler
  end
  
  it "should kill the app on a fatal error" do 
    lambda { @eco << [:fatal_error]}.should raise_error(SecurityError)
    lambda { out = @eco << [:is_alive]}.should raise_error(StateProcessor::StateProcessorExceptions::StateProcessorNotFound)
  end

  it "should not kill the app, but should raise on a not_so_fatal" do
    out = 'Bob'
    lambda { out = @eco << [:not_so_fatal_error]}.should raise_error(StandardError)
    out.should == "Bob"
    out = @eco << [:is_alive]
    out.should == true
  end

  it "should call the error handler on not_fatal_at_all" do
    out = @eco << [:not_fatal_at_all_error]
    out.should == "got an error RecoverableError"
  end

  after :each do
    @eco.kill_thread rescue nil
  end
    
end


    
    


