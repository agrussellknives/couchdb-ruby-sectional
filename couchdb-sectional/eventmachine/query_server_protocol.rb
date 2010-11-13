require 'eventmachine'

module Enumerable
  def recursive_symbolize
    inject(self.class.new) do |memo,(k,v)|
      begin
        if memo.respond_to? :<<
          memo << k.recursive_symbolize
        else
          new_key = k.to_sym rescue k
          new_val = v.recursive_symbolize rescue v
          memo.store(new_key,new_val)
        end
      rescue NoMethodError
        memo << k.to_sym rescue k
      end
      memo
    end
  end
end

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
     command = (JSON.parse data if data).recursive_symbolize
    rescue JSON::ParserError => e
      #an unparseable command - make "run" go fatal.
      command = [""]
    rescue => e
      raise e
    end
    p command
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
