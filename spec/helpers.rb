require_relative '../couchdb-sectional/couchdb_core/utils/metaid'
require_relative '../couchdb-sectional/couchdb_core/utils/aspects'

require 'em/pure_ruby'

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
      puts 'recieve data called on eco'
      send_data @state_processor.process(cmd)
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
          puts "event-machine started with lib #{EM.library_type}"
          begin
            puts 'trying to attach'
            EventMachine.bind_string(@stio, PassThroughClient)
          rescue => e
            debugger; 1
            puts e
          end
        end
      end
      @em_thread.abort_on_exception = true
      @em_thread.run
      raise StateProcessorError, "Couldn't start the reactor loop" unless wait_for_em_start_up
    end
    self
  end

  def kill_thread
    @em_thread.kill #KILL KILL KILL KILL
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
    msg = Marshal.dump(msg)
    debugger
    @stio << msg 
  end
end


#let's fuckup eventmachine!
#
module EventMachine
  class EvmaStringIO < StreamObject
    def initialize io
      # define eventmachine IO extensions on this object only 
      # i could actually just monkey patch the stringIO class.
      # we'll see
      io.meta_eval do
        extend Forwardable
        def_delegator :@my_selectable, :close_scheduled?
        def_delegator :@my_selectable, :select_for_reading?
        def_delegator :@my_selectable, :select_for_writing?
        def_delegator :@my_selectable, :eventable_read
        def_delegator :@my_selectable, :eventable_write
        def_delegator :@my_selectable, :uuid
        def_delegator :@my_selectable, :send_data
        def_delegator :@my_selectable, :schedule_close
        def_delegator :@my_selectable, :get_peername
        def_delegator :@my_selectable, :send_datagram
        def_delegator :@my_selectable, :get_outbound_data_size
        def_delegator :@my_selectable, :set_inactivity_timeout
        def_delegator :@my_selectable, :heartbeat
      end        

      io.meta_def :fcntl do |cmd,arg|
        #muhahahah
        case cmd
        when Fcntl::F_GETFL
          #makes no difference, arg is ignored
          return Fcntl::O_NONBLOCK | Fcntl::O_RDWR
        when Fcntl::F_SETFL
          #yes, yes, you set me to non blocking
          return Fcntl::O_NONBLOCK
        else
          raise NotImplementError, "EvmaStringIO doesn't support other fcntl commands"
        end
      end
              
      debugger;1
      # now call super
      super
      @pending = true
    end

    def select_for_writing?
      true
    end

    def select_for_reading?
      @io.size > 0 ? true : false
    end

    def self.connect str
      EvmaStringIO.new str
    end
  end

  class << self
    def connect_string str
      EvmaStringIO.connect str
    end
  end

  def self.bind_string string, handler, *args
    klass = klass_from_handler(Connection,handler,*args)
    s = connect_string string
    c = klass.new s, *args
    @conns[s] = c
    block_given? and yield c
    c
  end

end
