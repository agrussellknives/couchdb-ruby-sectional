require 'eventmachine'

module CouchDBQueryServerProtocol
  include EM::Protocols::LineText2
  
  @run = nil

  def unbind
    #TODO change this to stop the particular server, but not
    #the ruby section itself
    EventMachine::stop_event_loop
  end
  
  def receive_line data
    begin
     command = JSON.parse data if data
    rescue JSON::ParserError => e
      #an unparseable command - make "run" go fatal.
      command = [""]
    rescue => e
      raise e
    end
    @run.call(command)
  end
  
  def send_data data
    # we absolutely must write to the real stdout
    # all the time.  do not trust the module. it doth
    # speak with forked tounge
    STDOUT.puts data.to_json
  end
  
  def run &block
    @run = block
  end
  
end
