relative_require './helpers'
require 'couchrest'

class HelloWorld < SectionalApp

  protocol RubyPassThroughProtocol

  commands do
    on :hello do |name|
      Greeting << :say_hello
    end

    on :goodbye do |name|
      Greeting << :say_goodbye
    end

    consume_command!
    on do |name|
      Headline << :name, name
    end
    
    return render_all
  end
end

class Greeting < Section
  db :hello_world

  def say_hello
    @greeting = "Hello Bright World!"
  end

  def say_goodbye
    @greeting = "Goodbye Cruel World"
  end

  commands do
    return_after do
      on :say_hello
      on :say_good
    end
  end
end

describe "simple section app should say hello and goodbye"
  before(:all) do
    @couch = CouchRest.new('127.0.0.1:5984')
    @couch = @couch.create_db 'hello_world'
    data = File.open('./hello_world/data.json').read do |f|
      JSON.parse(f)
    end
    @couch.bulk_save(data["docs"])
  end
  
  before do
    @co = CommObject.new HelloWorld
  end

  it "should say hello world" do
    out = @co << :hello, "Norbert"
    out.should == "Yo, yo, yo, My name is Norber and I'm here to say Hello World!"
  end

  it "should say goodbye world" do
    out = @co << :goodbye, "Stephen"
    out.should == "Yo, yo, yo, My name is Stephen and I'm here to say Goodbye Cruel World!"
  end

  after(:all) do
    @couch.delete
  end
end
    
  
