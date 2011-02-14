require_relative './helpers'
require 'couchrest'
require 'rest_client'
require 'thin'

resulting_html = <<-HTML
  <html>
    <body>
      <div class="templated_greeting">
        <h1> Hello There foo </h1>
        <a href="goodbye/foo">say goodbye</a>
        <a href="conversation-stick_around">stick aroud</a>
      </div>
      <div class="templated_greeting">
        <h1> Hello There bar </h1>
        <a href="goodbye/foo">say goodbye</a>
        <a href="conversation-stick_around">stick aroud</a>
      </div>
    </body>
  </html>
HTML

class HelloWorld < SectionalApp
  template do
    <<-HTML
      <html>
        <body>
          {{TemplatedGreeting}}
        </body>
      </html>
    HTML
  end

  section :TemplatedGreeting do
    template :hello do
    <<-HTML
      {{.names}}
      <h1> Hello There {{name}} </h1>
      <a href="goodbye/{{name}}">say goodbye</a>
      <a href="{{Conversation::stick_around}}">stick around</a>
      {{names}}
    HTML
    end

    template :goodbye do
    <<-HTML
      <h1>Goodbye then {{name}}</h1>
    HTML
    end
  end
  
  on :error do |okay|
    debugger
    raise Error404
  end
 
  commands do
   
    on :forget_me do |name|
      @name = name
      return "I will remember #{@name}"
    end

    on :remember_my_session do |name|
      unless @name
        return "I never knew you!"
      else
        return "I remember #{@name}"
      end
    end

    on :remember_my_spot do |name|
      answer "Hello #{name} how are you?" do
        on :fine do
          answer "That's great!"
        end
        
        on :not_so_good do
          answer "That's too bad."
        end

        on :suicidal do
          return "Bye then"
        end
      end
    end

    return_after do
      on :forget_me do |name|
        @name = name
        return "I remember #{@name}"
      end

      on :remember_me do |name|
        return "I forgot #{@name}"
      end

      on :hello do |name|
        send Greeting, [:say_hello] 
      end

      on :goodbye do |name|
        send Greeting, [:say_goodbye] 
      end
    end
    
    switch_section TemplatedGreeting do
      on :template_hello do |*names|
        @names = names
        answer with :hello do
          on :goodbye do |name|
            @name = name
            return with :goodbye
          end
        end
      end
    end
    
    raise Error404 
  end
end

class Conversation < Section
  template do
    <<-HTML
      <h1> What's up {{name}}?</h1>
    HTML
  end

  commands do
    on :stick_around do |name|
      @name = name
      return default
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
      on :say_goodbye
    end
  end
end

describe "simple section app should say hello and goodbye" do
  before(:all) do
    @t = Thread.new do 
      @ts = Thin::Server.start('127.0.0.1',3000) do
        use Rack::CommonLogger
        use Rack::Session::Cookie,  :key => 'rack.session',
                                    :domain => '127.0.0.1'
        run HelloWorld.new
      end
    end
    # wait for server to start up
    sleep 3
  end

  it "should log errors" do
    out = RestClient.get 'http://127.0.0.1:3000/error'
    out.response_code.should == 404
  end

  it "should say hello world" do
    out = RestClient.get 'http://127.0.0.1:3000/hello/Norbert'  
    out.should == "Hello Bright World!"
  end

  it "should say goodbye world" do
    out = RestClient.get 'http://127.0.0.1:3000/goodbye/Norbert'
    out.should == "Goodbye Cruel World"
  end

  it "should forget across sessions, but remember sessions" do
    out = RestClient.get 'http://127.0.0.1:3000/forget_me/foo'
    out.should == "I will remember foo"
    cookies = out.cookies.dup
    out = RestClient.get 'http://127.0.0.1:3000/remember_my_session/bar'
    out.should == "I never knew you!"
    out = RestClient.get 'http://127.0.0.1:3000/remember_my_session/bar',{:cookies => cookies}
    out.should == "I remember foo"
  end

  it "should remember it's spot if I answer" do
    out = RestClient.get 'http://127.0.0.1:3000/remember_my_spot/Stephen'
    out.should == "Hello Stephen how are you?"
    out = RestClient.get 'http://127.0.0.1:3000/fine', {:cookies => out.cookies}
    out.should == "That's great!"
    out = RestClient.get 'http://127.0.0.1:3000/not_so_good', {:cookies => out.cookies}
    out.should == "That's too bad."
    out = RestClient.get 'http://127.0.0.1:3000/suicidal', {:cookies => out.cookies}
    out.should == "Bye then"
    out = RestClient.get 'http://127.0.0.1:3000/fine', {:cookies => out.cookies}
    out.response_code.should == 404
  end

  it "should forget between requests" do
    out = RestClient.get 'http://127.0.0.1:3000/forget_me/foo'
    out.should == "I remember foo"
    out = RestClient.get 'http://127.0.0.1:3000/remember_me/bar'
    out.should == "I forget"
  end

  it "should say hello world with a template" do
    pending
  end

  after(:all) do
    Thin::Server.stop
    @t.kill
  end
end
