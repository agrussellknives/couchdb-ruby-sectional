module CouchDB
  module Exceptions
    class HaltedFunction < StandardError; end
    class FatalError < StandardError; end
  end
end
