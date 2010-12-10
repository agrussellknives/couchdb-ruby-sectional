require_relative '../couchdb-sectional/state_processor'

require_relative 'helpers'

class PatternMatchingStateProcessing
  include StateProcessor
  include StateProcessor::StateProcessorWorker

  protocol RubyPassThroughProtocol

  commands do

    on anything, 1 do
      p 'on anything, 1 do'
      return :anything,1
    end

    on anywhere(:hello) do
      p 'on anywhere(:hello) do' 
      return "hello"
    end

    on _, 2 do
      p 'on _, 2 do'
      return :_, 2
    end

    on _(:hi) do
      p 'on _(:hi),2 do'  
      return :hi,2
    end

    on save_anything, :sa do |a|
      p 'on save_anything, :sa do |a|'  
      return a
    end

    on save_anything, :sa2 do |b,c|
      p 'on save_anything, :sa2 do |b,c|' 
      return b,c
    end

    on save_anywhere(:sa3), :sa4 do |a|
      p 'on save_anywhere(:hi), 1, 2 do |a|'  
      return a
    end
    
    on :sa, _!(:bar), _!(:foo), _!(:bob) do |b,f,bo|
      p 'on :sa, _!(:bar), _!(:foo), _!(:bob) do |b,f,bo|' 
      return [:sa, b,f,bo]
    end

    # match anything in the first position
    # match foo anywhere
    # match bar anywhwere and append it to the end of the argument list
    on _,_(:foo),_!(:bar) do |b,c|
      p 'on _,_(:foo),_!(:bar) do |b,c|' 
      return b,c
    end
  end
end

describe PatternMatchingStateProcessing, "should match patterns" do
  before do
    @co = CommObject.new PatternMatchingStateProcessing
  end

  it "should match anything in the first position" do
    out = @co << [:foo,1]
    out.should == [:anything,1]
    out = @co << [:bar,1]
    out.should == [:anything,1]
  end

  it "should match anywhere" do
    out = @co << [:foo,:hello,:bar]
    out.should == "hello"
    out = @co << [:bar,:foo,:hello]
    out.should == "hello"
  end

  it "should match using _ or anything" do
    out = @co << [:foo, 2]
    out.should == [:_,2]
    out = @co << [:bar,2]
    out.should == [:_,2]
  end

  it "should match anywhere with _" do
    out = @co << [:foo,:baz,:hi]
    out.should == [:hi,2]
    out = @co << [:foo,:hi,:baz]
    out.should == [:hi,2]
  end

  it "should save anything in the first position" do
    out = @co << [:anything,:sa]
    out.should == :anything
  end

  it "should save anything, appending it to the argument list" do
    out = @co << [:anything,:sa2,1]
    out.should == [1,:anything]
  end

  it "should save anywhere, truncating to length of blocks args" do
    out = @co << [:sa3, :sa4, :sa5]
    out.should == :sa5
  end
  
  it "should save multiple, appending it in the same order it was matched in" do
    out = @co << [:sa,:foo, :bar, :bob]
    out.should == [:sa,:bar,:foo,:bob]
  end

  it "should do multiple open-ended matches" do
    out = @co << [:anything,:bar,:foo,:last]
    out.should == [:last,:bar]
  end
end
