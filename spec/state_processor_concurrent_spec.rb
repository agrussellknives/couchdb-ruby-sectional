require_relative '../couchdb-sectional/state_processor'
require_relative 'helpers'

require 'eventmachine'
require 'uuidtools'


class PassServer < EventMachine::Connection
  
  SERVER_POOL = {}
  AnswerToken = StateProcessor::StateProcessorSection::AnswerToken

  def initialize *args
    super
  end

  def answer_token
    @answer_token ||= UUIDTools::UUID.random_create.to_s
  end
    

  def post_init
    puts '--pass server connection'
    @co = CommObject.new ConcurrentTest
  end

  def receive_data data
    data = eval data
    uuid = data.first rescue false

    if SERVER_POOL.has_key? uuid
      # remove the CO from the pool so it can be garbage collected
      data.shift
      @co = SERVER_POOL.delete(uuid)
    end
    
    res = @co << data
    
    answer = res.first rescue false
    if answer == AnswerToken
      SERVER_POOL[answer_token] = @co
      res[0] = answer_token
    end
    p res
    send_data Marshal.dump(res)
  end

  def unbind
    puts '--pass server disconnection'
  end
end

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

  protocol PassServer

  commands do
    on :test_ivar do |a|
      return test_instance_method_isolation(a)
    end

    on :test_ivar_pass do |a|
      answer test_instance_method_isolation(a) do
        on :test_instance_cont do
          return :instance_cont
        end
      end
    end

    on :test_class do |a|
      return test_class_method_sharing(a)
    end

    on :test_class_pass do |a|
      answer test_class_method_sharing(a) do
        on :test_class_cont do
          return :class_cont
        end
      end
    end

    on :stop do
      return :ok
      EM::stop
    end
  end
end

describe 'should work over the network' do
  before(:all) do
    @em = EventMachine::fork_reactor do
      EventMachine::start_server "127.0.0.1", 5050, PassServer
    end
    sleep 2
    # use a raw socket because i'm lazy
    @conn = TCPSocket.new "127.0.0.1", 5050
  end

  before(:each) do
    @conn = TCPSocket.new "127.0.0.1", 5050
  end

  it "should respond to data" do
    @conn << [:test_ivar,1]
    Marshal.load(@conn.recv(1000)).should == 2
  end

  it "should remember instance state on same connection" do
    @conn << [:test_ivar,1]
    Marshal.load(@conn.recv(1000)).should == 2
    @conn << [:test_ivar,1]
    Marshal.load(@conn.recv(1000)).should == 3
  end

  it "should forget instance state on new conneciton" do
    @conn << [:test_ivar,1]
    Marshal.load(@conn.recv(1000)).should == 2
    @conn2 = TCPSocket.new "127.0.0.1", 5050
    @conn2 << [:test_ivar,1]
    Marshal.load(@conn2.recv(1000)).should == 2
    @conn2.shutdown
  end

  it "should share class state across connections" do
    @conn << [:test_class,1]
    Marshal.load(@conn.recv(1000)).should == 2
    @conn2 = TCPSocket.new "127.0.0.1", 5050
    @conn2 << [:test_class,1]
    Marshal.load(@conn2.recv(1000)).should == 3
    @conn2.shutdown
  end

  it "should be able to do a continuation on an instance" do
    @conn << [:test_ivar_pass,1]
    res = Marshal.load(@conn.recv(1000))
    c_token = res.shift
    res.last.should == 2
    @conn << [c_token, :test_instance_cont]
    Marshal.load(@conn.recv(1000)).should == :instance_cont
  end

  after(:each) do
    @conn.shutdown
  end

  after(:all) do
    #kill the reactor
    @quit_con = TCPSocket.new "127.0.0.1", 5050
    @quit_con << [:quit]
  end
end


    

