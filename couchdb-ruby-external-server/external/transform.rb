require 'couch_db'
require 'couchrest'

class TransformRenderer < CouchDB::Design::ListRenderer    
  def initialize(proc, design, view)
    @results_mutex = Mutex.new
    @rows = Queue.new
    Thread.new do
      @head = External.db.view "#{design}/#{view}" do |row|
         @rows << row
      end 
    end
    @view_pager = Fiber.new do
      while @rows.length > 0 do
        Fiber.yield @rows.pop
      end
    end
  end
    
  def run(req)
    debugger
    first_row = @view_pager.resume
    @started = false
    @fetched_row = false
    @start_response = {"headers" => {}}
    @chunks = []
    tail = super(@head, req)
    get_row if ! @fetched_row
    @chunks.push tail if tail
    ["end", @chunks]
  end
  
  def get_row
    @view_page.resume
  end
  
  def send item
    log "sending #{item.to_json}"
    #@db.save item.to_json
  end
end


module ExternalCouch::External
  def transforms design, transform, view, req
    func = ExternalCouch::Sandbox.make_proc @db["_design/#{design}"]['transforms'][transform]
    return func, 500 unless func.is_a? Proc
    TransformRenderer.new(func, design, view).run(req)
  end
end
  
