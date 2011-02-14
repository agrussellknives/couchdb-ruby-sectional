require_relative '../couchdb-sectional/couchdb_core/utils/metaid'
require_relative '../couchdb-sectional/couchdb_core/utils/aspects'
require_relative '../couchdb-sectional/state_processor'
require_relative '../couchdb-sectional/thin_adapter'
require_relative '../couchdb-sectional/section'

require 'base64'
require 'forwardable'
require 'thread'
require 'timeout'

module ClockTick
  def clock_tick
    @chars ||= %w{ | / - \\}
    $stdout.print @chars[0]
    sleep 0.1
    $stdout.print "\b"
    @chars.push @chars.shift
  end
end

module RubyPassThroughProtocol
  def <<(cmd)
    @state_processor.process(cmd)
  end

  def error(cmd)
    [:error, cmd]
  end
end

module RubyEventPassThroughProtocol
  def to_processor(cmd)
    begin
      res = @state_processor.process(cmd)
      succeed res
    rescue StandardError => e
      set_deferred_status :failed, e
    end
  end

  def error(cmd)
    puts "protocol error called" 
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
  include EM::Deferrable
  include RubyEventPassThroughProtocol
  
  class ResponseRecieved < StandardError; end

  class << self
    @@em_thread = nil 

    def start_eco_reactor
      if EM.reactor_running? and not @@em_thread
        EM.stop
        loop { break if not EM.reactor_running? }
      end

      unless EM.reactor_running?
        @@em_thread = Thread.new do
          begin
            EM.run
          rescue Exception => e
            # fatal errors are raised on the main thread
            Thread.main.raise e
          end
        end
        loop { break if EM.reactor_running? }
      end
    end
  end
   
  def initialize stp
    @state_processor = StateProcessor[stp].new
    @state_processor.class.protocol = RubyPassThroughProtocol 
    @initializing_thread = Thread.current
    # ECO requires error handling in the event loop
    # unless we started this reactor - kill it and start
    # it again
    EventedCommObject.start_eco_reactor
    self
  end

  def << msg
    begin
      #bad mojo unless the reactor is running... 
      raise StateProcessor::StateProcessorExceptions::StateProcessorNotFound unless @@em_thread.status

      this_thread = Thread.current

      callback do |res|
        set_deferred_status nil 
        this_thread.raise ResponseRecieved, res 
      end
     
      errback do |e|
        set_deferred_status nil
        this_thread.raise e
      end
     
      # run the processor as a deferrable
      EM.schedule do
        self.to_processor(msg)
      end
      
      # wait for the response to fake blocking
      # style calls
      loop { break if not EM.reactor_running? }
    
    rescue ResponseRecieved => e
      e.message == e.class.to_s ? nil : e.message
    end
  end
end


