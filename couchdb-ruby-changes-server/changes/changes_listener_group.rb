require 'eventmachine'

class ChangesListenerGroup
  def initialize(default_host = "http://127.0.0.1:5984")
    @default_host = default_host
    @changes_listeners = []
    # start the reactor loop
    unless EM.reactor_running?
      Thread.new { EM.run }
      @reactor_thread = EM.reactor_thread
    else
      @reactor_thread = EM.reactor_thread
    end
  end
  
  def add(db, options = {}, &block)
    db, port, host = db.sub(/^http:\/\//,'').split(/[:\/]/).reverse
    self << ChangesListener.new("#{@default_host}/#{db}", options, &block)
  end
  
  def <<(obj)
    @changes_listeners << obj
  end
  
  def [](i)
    @changes_listeners[i]
  end
  
  def start(i=nil)
    range = int_to_range(i,@changes_listeners.size)
    
    range.each do |i|
      listener = @changes_listeners[i]
      listener.listen
    end
  end
  
  def running_listeners()
    @changes_listeners.list
  end
  
  def stop(i=nil)
    range = int_to_range(i,@changes_listeners.size)
    
    range.each do |i|
      listener = @changes_listeners[i]
      listener.stop_listening
    end
  end
  
  def panic_stop
    # this is pretty drastic - there's no cleanup or ability for the connections
    # to cleanup after themselves
    @reactor_thread.kill
  end
  
  private
  
  def int_to_range(i,size)
    range = 0..size
    (range = (i.respond_to? :each) ? i : (i..i)) if i
    range
  end
  
end