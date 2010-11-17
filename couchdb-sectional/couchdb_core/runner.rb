module CouchDB
  class Runner
    include CouchDB::Exceptions
    
    def initialize(func, worker = self)
      @func = func
      @worker = worker
    end
   
    def run(*args)
      begin
        # return the raw error from sandbox if our proc hasn't compiled.
        return @func unless @func.is_a?(Proc)
        results = @worker.instance_exec *args, &@func
        if @results then @results else results end
      rescue HaltedFunction => e
        $error.puts(e) if CouchDB.debug
        e.message 
      rescue FatalError => e
        $error.puts(e) if CouchDB.debug
        # this is a little messy, since we subvert all of our complicated
        # abstraction and just kill the bastard.
        CouchDB.write e.message
        CouchDB.exit
      rescue => e
        CouchDB.log [e.class.to_s,e.message]
        (CouchDB.log('Waiting for debugger....'); debugger) if CouchDB.stop_on_error
        results = []
      end
    end

  end
end
