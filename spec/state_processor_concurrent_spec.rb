require_relative '../couchdb-sectional/state_processor'
require_relative 'helpers'

require 'eventmachine'
require 'uuidtools'

class ConcurrentTest
  include StateProcessor
  include StateProcessorWorker

  def test_instance_method_isolation(a)
    @ivar_count ||= 1
    @ivar_count += a
    return @ivar_count
  end

  def test_class_method_sharing(a)
    @@cvar_count ||= 1
    @@cvar_count += a
  end

  commands do
    on :test_ivar do |a|
      return test_instance_method_isolation(a)
    end

    on :test_ivar_pass do |a|
      answer test_instance_method_isolation(a)
    end

    on :test_class do |a|
      return test_class_method_sharing(a)
    end

    on :test_class_pass do |a|
      answer test_class_method_sharing(a)
    end

    on :stop do
      return :ok
    end
  end
end

class PassServer < EventMachine::Connection
  
  SERVER_POOL = {}

  def initialize *args
    super
  end

  def answer_token
    @answer_token ||= UUIDTools::UUID.random_create.to_s
  end
    

  def post_init
    puts '--pass server started'
    @co = CommObject.new ConcurrentTest
  end

  def receive_data data
    data = eval data
    uuid = data.first rescue false

    if SERVER_POOL.has_key? uuid
      @co = SERVER_POOL[uuid]
    end
    
    res = @co << data
    
    answer = res.first rescue false
    if res.first == AnswerToken
      SERVER_POOL[answer_token] = @co 
      res.unshift answer_token
    end
    send_data res 
  end

  def unbind
    puts '--pass server killed'
  end
end

describe 'should work over the network' do
  before(:all) do
    @em = EventMachine::fork_reactor do
      EventMachine::start_server "127.0.0.1", 5050, PassServer
    end
    sleep 2
    @conn = TCPSocket.new "127.0.0.1", 5050
  end

  before(:each) do
    @conn = TCPSocket.new "127.0.0.1", 5050
  end

  it "should respond to data" do
    @conn << [:test_ivar,1]
    (eval @conn.recv(1000)).should == 2
  end

  it "should remember instance state on same connection" do
    @conn << [:test_ivar,1]
    (eval @conn.recv(1000)).should == 2
    @conn << [:test_ivar,1]
    (eval @conn.recv(1000)).should == 3
  end

  it "should forget instance state on new conneciton" do
    @conn << [:test_ivar,1]
    (eval @conn.recv(1000)).should == 2
    @conn2 = TCPSocket.new "127.0.0.1", 5050
    @conn2 << [:test_ivar,1]
    (eval @conn2.recv(1000)).should == 2
    @conn2.shutdown
  end

  after(:each) do
    @conn.shutdown
  end

  after(:all) do
    Process.kill(9,@em)
  end
end


    

