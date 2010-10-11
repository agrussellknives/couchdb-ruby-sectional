module CouchDB
  module Sandbox
    extend self
    
    def initialize
      @safe = true
    end
    
    def safe
      @safe
    end
    
    def safe=(bool)
      @safe = !! bool
    end
    
    def make_proc(string)
      begin
        value = run(string)
        unless value.is_a?(Proc)
          value = ["error", "compilation_error", "expression does not eval to a proc: #{string}"]
        end
      rescue SyntaxError => e
        value = ["error","compilation_error","#{e.class.name}: #{e.message}"]
      end
      value
    end
    
    def run(string)
      raise SyntaxError, "Function does not exist or contains no code" if string == nil
      if safe
        lambda { $SAFE=4; eval(string) }.call
      else
        eval(string)
      end
    end
    
  end
end
