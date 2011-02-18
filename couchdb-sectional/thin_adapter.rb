require 'thin'
require_relative 'eval_debugger'
require_relative 'state_processor'

module HTTPApplication
  # this doesn't actually do eventmachin protocol type stuff, since we leverage
  # thin's HTTP EM protocol, but we need it just to let
  # our section know what protocol it's in
  
  def error e
    @logger.error("===Application Error===")
    @logger.error("#{e} :  #{e.message} \n #{e.backtrace}")
    @logger.error("=======================")
    e
  end
  module_function :error
end

module SectionalHTTPApplication 
  def call(env)
    req = Rack::Request.new(env)
    puts @state_processor_bag
    unless req.session[:id]
      debugger
      scp = @state_processor_class.new
      @state_processor_bag[scp.object_id] = scp
      req.session[:id] = scp.object_id
    else
      scp = @state_processor_bag[req.session[:id]]
      scp.last_access = Time.now
    end
    
    cmd = env['REQUEST_PATH'].split('/').collect { |pc| pc.to_sym}[1..-1]

    begin
      body = scp.process(cmd)
    rescue => e
      [500, {:content_type => "text/html" }, [e, e.backtrace].to_s ]
    else
      [200, {:content_type => "text/html" }, body]
    end
  end

  module ClassMethods
    def session_timeout time=600
      @@time = time
    end
  end

  def reap_sessions
    @state_processor_bag.delete_if do |sp|
      Time.now - sp.last_access > @@time
    end
  end
end

