module CouchDB
  class Runner
   
    class HaltedFunction < StandardError; end
    class FatalError < StandardError; end

    def initialize(func)
      @func = func
    end
    
    def run(*args)
      begin
        # return the raw error from sandbox if our proc hasn't compiled.
        return @func unless @func.is_a?(Proc)
        results = instance_exec *args, &@func
        if @results then @results else results end
      rescue HaltedFunction => e
        $error.puts(e) if CouchDB.debug
        @error
      rescue => e
        log [e.class.to_s,e.message]
        (log('Waiting for debugger....'); debugger) if CouchDB.stop_on_error
        results = []
      end
    end

    def throw(error, *message)
      begin
        @error = if [:error, :fatal, "error", "fatal"].include?(error)
          errorMessage = ["error", message].flatten
          raise FatalError, errorMessage if [:fatal,"fatal"].include?(error)
          errorMessage
        else
          {error.to_s => message.join(', ')}
        end
        raise HaltedFunction
      rescue FatalError => e
        CouchDB.write(e.message)
        CouchDB.exit
      end
    end

    def log(thing)
      CouchDB.write(["log", thing.to_json])
    end

  end
end
