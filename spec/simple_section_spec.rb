require_relative './helpers'
require 'couchrest'
require 'rest_client'
require 'thin'

class HelloWorld < SectionalApp

  commands do
    on :hello do |name|
      send Greeting, [:say_hello] 
    end

    on :goodbye do |name|
      send Greeting, [:say_goodby] 
    end

  end
end

class Greeting < Section
  
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

describe "simple section app should say hello and goodbye" do
  before(:all) do
    debugger;1
    @t = Thread.new do 
      Thin::Server.start('127.0.0.1',3000) do
        use Rack::CommonLogger
        run HelloWorld.new
      end
    end
    sleep 3
  end

  it "should say hello world" do
    out = RestClient.get 'http://127.0.0.1:3000/hello/Norbert'  
    out.should == "Hello Bright World!"
  end

  it "should say goodbye world" do
    out = RestClient.get 'http://127.0.0.1:3000/goodbye/Norbert'
    out.should == "Goodby Cruel World"
  end

  after(:all) do
    @t.kill
  end
end
    
  
