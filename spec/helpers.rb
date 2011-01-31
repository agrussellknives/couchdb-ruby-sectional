require_relative '../couchdb-sectional/couchdb_core/utils/metaid'
require_relative '../couchdb-sectional/couchdb_core/utils/aspects'
require_relative '../couchdb-sectional/state_processor'
require_relative '../couchdb-sectional/thin_adapter'
require_relative '../couchdb-sectional/section'

require 'base64'
require 'forwardable'
require 'thread'

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


class EventedCommObject 
  
  class PassThroughClient < EM::Connection
    include EM::Protocols::LineText2
    extend Forwardable

    def_delegators :@eco, :encode, :decode, :ap_end, :state_processor
    
    def initialize eco
      @eco = eco
    end
    
    def receive_data data
      puts "recieved #{decode(data)}"
      data = state_processor.process(decode(data))
      puts "got #{data} sending it back"
      send_data data
    end

    def send_data data
      puts "trying to send #{encode(data)}"
      ap_end.puts(encode(data))
    end
  end

  def encode obj
    Base64.encode64(Marshal.dump(obj)) 
  end
  
  def decode obj
    Marshal.load(Base64.decode64(obj)) 
  end

  attr_accessor :state_processor, :ap_end

  def initialize stp
    @ec = IO.popen('cat','r+')
    @ap_end = IO.popen('cat','r+')
     
    @state_processor = StateProcessor[stp].new()
    @state_processor.class.protocol = PassThroughClient
    @initializing_thread = Thread.current
    @em_thread = Thread.new do
      loop do
        begin
          $stdout.puts "in front of run"
          $stdout.puts "#{EM.reactor_running?}"
          EM.run do
            $stdout.puts "attached eco"
            EM.attach @ec, EventedCommObject::PassThroughClient, self
          end
        rescue StandardError => e
          EM.stop_event_loop
          @initializing_thread.raise e
        rescue Exception => e
          raise e
        end
      end
    end
    @em_thread.abort_on_exception = true
    self
  end

  def kill_thread
    @em_thread.kill #KILL KILL KILL KILL
  end

  def << msg
    begin
      raise StateProcessor::StateProcessorExceptions::StateProcessorNotFound unless @em_thread.status
      puts "trying to pass message #{msg} with thread #{@em_thread.status}"
      @ec << encode(msg)
      res = @ap_end.gets 
      decode(res) if res
    rescue => e
      raise e
    end
  end
end


