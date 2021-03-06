require 'ruby-debug'

#stdlib
require 'json'
require 'eventmachine'


# utility
require_relative 'eval_debugger'

# couchdb requires
%w(exceptions runner sandbox arguments).each {|mod| require_relative "couchdb_core/#{mod}" }

#event machine
require_relative './state_processor'
require_relative './state_processor/protocols/query_server_protocol'

require_relative './couchdb_core/utils/aspects'
require_relative './couchdb_core/utils/metaid'

module CouchDB
  include Arguments
  include StateProcessor::StateProcessorExceptions
  extend self
  $realstdout = $stdout
  $realstdin = $stdin
  $stdout = $stderr
  $error = $stderr
  
  attr_accessor :debug, :wait_for_connection, :stop_on_error
  
  def state= key
    @state = key.intern
  end
  
  def state
    return @state 
  end
  
  def stderr_to=(val)
    $error = File.open(val,'a+')
  end
  
  def start initial_state = nil
    unless (initial_state and StateProcessor::StateProcessorFactory.knows_state? initial_state) then
      raise StateProcessorInvalidState,'CouchLoop was started in an unknown or nil state.'
    end
    state = initial_state
    (log 'Waiting for debugger...'; debugger) if wait_for_connection  
    EventMachine::run do
      @pipe = EM.attach $stdin, StateProcessor::StateProcessorFactory[state].protocol do |pipe|
        pipe.state_processor_root = StateProcessor::StateProcessorFactory[state].new
        pipe.run do |command|
          begin
            write pipe.state_processor_root.process(command) 
          rescue StateProcessorDoesNotRespond,
                 StateProcessorCannotPerformAction, 
                 StateProcessorError => e
            exit e 
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

def commands_for key = :default, protocol = CouchDBQueryServerProtocol, &block
  puts 'called couchdb commandsfor'
  StateProcessor.commands_for(key, protocol, &block)
end
