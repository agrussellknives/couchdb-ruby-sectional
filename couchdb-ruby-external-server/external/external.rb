require 'couchrest'
require 'couch_db'

module ExternalCouch
  module External
    include CouchDB::Design
    extend self
    
    attr_accessor :db
    
    @db = nil
    
    def handle command
      debugger
      db, op, *rest = *command['path']
      req = command
      @db = CouchRest.new(ExternalCouch::ROOT)[db]
      op = op[1..-1]+'s' #naive pluralize and strip leading _
      begin
        send op, *rest, req
      rescue ArgumentError => e
        raise ArgumentError, 404
      end
    end
  end
end