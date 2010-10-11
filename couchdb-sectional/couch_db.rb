require 'ruby-debug'
require 'eval-debugger'

#stdlib
require 'json'
require 'eventmachine'


# couchdb requires
%w(runner sandbox arguments).each {|mod| require "#{File.dirname(__FILE__)}/couchdb_core/#{mod}" }

#event machine
%w(query_server_protocol state_processor).each {|mod| require "#{File.dirname(__FILE__)}/eventmachine/#{mod}" }

module CouchDB
  class UnknownStateError < StandardError; end
  include Arguments
  extend self
  $realstdout = $stdout
  $realstdin = $stdin
  $stdout = $stderr
  $error = $stderr
  
  STATE_PROCESSORS = {}
  
  attr_accessor :debug, :wait_for_connection, :stop_on_error
  
  def state= key
    @state = key.intern
  end
  
  def state key = :default, protocol = CouchDBQueryServerProtocol, &block
    # this method does double duty.
    return @state unless key and block_given?
    
    key = key.intern
    if block_given? then
      STATE_PROCESSORS[key] = StateProcessorFactory.create(key, protocol, &block)
    else
      STATE_PROCESSORS[key] = StateProcessorFactory.create(key, NilProtocol) do |command|
        puts command
      end
    end
  end
  
  def stderr_to=(val)
    $error = File.open(val,'a+')
  end
  
  def start initial_state = nil
    unless (initial_state and STATE_PROCESSORS.has_key? initial_state.intern) then
      raise UnknowStateError 'CouchLoop was started in an unknown or nil state.'
    end
    state = initial_state
    (log 'Waiting for debugger...'; debugger) if wait_for_connection  
    EventMachine::run do
      @pipe = EM.attach $stdin, STATE_PROCESSORS[state].protocol do |pipe|
        pipe.run do |command|
          begin 
            debugger 
            write STATE_PROCESSORS[state].new.process(command)
          rescue ProcessorDelegatesTo => e 
            puts "switching state" 
            state = e.state
            retry
          rescue ProcessorDoesNotRespond, ProcessorExit => e
            exit :error, e.to_s 
          end
        end
      end
    end
  end
  
  def log(thing)
    if @pipe then
      @pipe.send_data(["log", thing.to_json])
    else
      $error.puts ["log",thing.to_json]
    end
  end
  
  def exit(type = nil,msg = nil)
    @pipe.send_data([type,msg]) if type || msg
    Process.exit()
  end

  def write(response)
    @pipe.send_data response
  end
  
end

def commands_for key, protocol = CouchDBQueryServerProtocol, &block
  CouchDB.state key, protocol, &block
end

