require_relative '../couchdb-sectional/state_processor'
require 'eventmachine'

module RubyPassThroughProtocol
  def <<(cmd)
    @state_processor.process(cmd)
  end

  def error(cmd)
    [:error, cmd]
  end
end

class CommObject
  include RubyPassThroughProtocol
  attr_accessor :state_processor
  def initialize stp 
    @state_processor = StateProcessor[stp].new
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

  protocol RubyPassThroughProtocol

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
    end
  end
end

module PassServer
  def post_init
    @mco = CommObject.new ConcurrentTest
  end

  def receive_data data
    data = eval data
    send_data((@mco << data).to_s)
  end

  def unbind
    # don't need to do anything
  end
end

describe 'should work over the network' do
  before(:all) do
    @em = Thread.new do
        EM.run do
          EventMachine::start_server "127.0.0.1", 5050, PassServer
        end
      end
    sleep 2 
  end

  before(:each) do
    tries = 0
    begin
      @conn = TCPSocket.new "127.0.0.1", 5050
    rescue Errno::ECONNREFUSED 
      tries += 1
      retry if tries < 5
    end
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

  it "should handle a few connections at once" do
    results = []
    tg = ThreadGroup.new 
    mutex = Mutex.new
    srand(1)
    10.times do
      t = Thread.new do
        conn = TCPSocket.new "127.0.0.1", 5050
        a,b = [rand(10), rand(10)]
        conn << [:test_ivar,a]
        c = conn.recv(1000)
        conn << [:test_ivar,b]
        d = conn.recv(1000)
        mutex.synchronize do
          results << { :a => a, :b => b, :c => c.to_i, :d => d.to_i}
        end
      end
      tg.add t
    end
    # wait for thread to complete
    loop do 
      stati = tg.list.collect do |t|
        t.status if t.status
      end
      break if stati.length == 0
    end
   
    results.each do |r|
      r[:c].should == r[:a]+1
      r[:d].should == r[:b] + r[:a] + 1
    end
  end

  it "should forget instance state on new conneciton" do
    @conn << [:test_ivar,1]
    (eval @conn.recv(1000)).should == 2
    @conn2 = TCPSocket.new "127.0.0.1", 5050
    @conn2 << [:test_ivar,1]
    (eval @conn2.recv(1000)).should == 2
    @conn2.shutdown
  end

  it "should share class state across connections" do
    @conn << [:test_class,1]
    (eval @conn.recv(1000)).should == 2
    @conn2 = TCPSocket.new "127.0.0.1", 5050
    @conn2 << [:test_class,1]
    (eval @conn2.recv(1000)).should == 3
    @conn2.shutdown
  end

  after(:each) do
    @conn.shutdown
  end

  after(:all) do
    @em.kill
  end
end


    

