require "active_support"
require "eventmachine"
require "em-http"
require "json"

# ChangesListener
class ChangesListener
  def initialize db, options = {}, &block
    db, port, host = db.sub(/^http:\/\//,'').split(/[:\/]/).reverse
    if(port =~ /\./) then
      host = port; 
      port = "5984"   # ports don't have periods
    end
    
    options.reverse_merge! ({:feed => nil,
                             :since => nil,
                             :heartbeat => nil,
                             :style => :all_docs,
                             :filter => nil})
    
    # we have to define our :connect method on the eigenclass,
    # which has access to instance variables, but not the block
    # locals, so we copy them to instance vars here.
    @options = options.delete_if { |k,v| not v }
    @changes_url = "http://#{host}:#{port}/#{db}/_changes"
    @block = block
    
    
    class << self
      define_method :connect do
        EM.next_tick do
          @listener_client = EventMachine::HttpRequest.new(@changes_url).get :query => @options, :timeout => 0
          @listener_client.cancel_timeout #no timeout for changes listeners, as that makes no damn sense
          
          if @options[:feed].to_s != :continuous.to_s then
            # for single get and longpoll changes.
            @listener_client.callback do
              if @listener_client.response_header.status == 200
                changes = JSON.parse(@listener_client.response)
                if changes.has_key? 'results' then
                  changes['results'].each do |change|
                    @block.call change['seq'], change['id'], change['changes'], false || changes['deleted'], changes['last_seq']
                  end
                end
              else
                # received a non-200 response, chances are good we should quit
                error = JSON.parse(@listener_client.response)
                $stderr.puts @listener_client.response_header.status, error.inspect
                @listner_client.close_connection
              end
              @listener_client.close_connection 
            end
          else
            @listener_client.stream do |data|
              changes = JSON.parse(data)
              @block.call changes['seq'], changes['id'], changes['changes'], false || changes['deleted']
            end
          end
          @listener_client.errback do
            if @listener_client.error? then
              $stderr.puts "#{@listener_client} called error."
              $stderr.puts @listener_client.response_header.status, @listener_client.error
              @listener_client.close_connection
              EM.stop
            end
          end
        end
      end
    end
    
    # define an after hook to disconnect if the @feed is single.
  end
  
  def log(msg)
    $stderr.puts msg
  end

  def listen
    if EM.reactor_running? then
      connect
    else
      Thread.new(Thread.current) do |parent|
         begin
           EM.run 
         rescue => e
           debugger
           $stderr << e
         end
      end
      connect
    end
  end
  
  def status(err='')
    unless EM.reactor_running? then
      err.replace "Reactor not running"
      return false
    end
    if @listener_client.error? then
      err.replace "Listener closed or has error"
      return false
    end
    err.replace "Listening"
    return true
  end
  
  def stop_listening
    @listener_client.close_connection
  end
    
end