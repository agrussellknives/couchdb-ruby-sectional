require_relative '../couchdb-sectional/couchdb_core/utils/metaid'
require_relative '../couchdb-sectional/couchdb_core/utils/aspects'


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
  module PassThroughClient
    def post_init
      puts 'pass through client inited'
    end

    def receive_data data
      @state_processor.process(cmd)
    end

    def unbind
      puts 'pass through client killed'
    end
  end

  include PassThroughClient
  include StateProcessor::StateProcessorExceptions

  def initialize stp
    @stio = StringIO.new ''
    #thank you 1.9 for fucking up stringio
    def @stio.fileno
      self
    end

    @state_processor = StateProcessor[stp].new()
    @state_processor.class.protocol = PassThroughClient
    unless EM.reactor_running?
      @em_thread = Thread.new do
        EventMachine.run do
          puts 'event-machine started'
          begin
            debugger
            EventMachine.attach(@stio,PassThroughClient)
          rescue => e
            debugger;1
          end
        end
      end
      @em_thread.abort_on_exception = true
      @em_thread.run
      raise StateProcessorError, "Couldn't start the reactor loop" unless wait_for_em_start_up
    end
    self
  end

  def wait_for_em_start_up
    slept_time = 0
    started = while slept_time < 15 
      break true if EM.reactor_running?
      sleep 0.1
      slept_time += 0.1
    end
    # coerce to real boolean
    !!started
  end

  def << (msg)
    @stio << Marshal.dump(msg)
    Marshal.load(out = @stio.gets)
  end
end
