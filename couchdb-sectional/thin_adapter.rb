require 'thin'
require_relative 'eval_debugger'
require_relative 'state_processor'

module HTTPApplication
  # this doesn't actually do protocol type stuff, since we leverage
  # thin's HTTP EM protocol, but we need it just to let
  # our section know what protocol it's in
end

module SectionalHTTPApplication 
  def call(env)
    unless @state_processor
      scp = StateProcessor[self.class]
      scp.protocol= HTTPApplication
      @state_processor ||= scp.new
    end

    env['METHOD'] == 'HEAD'
    

    cmd = env['REQUEST_PATH'].split('/').collect { |pc| pc.to_sym}[1..-1]

    begin
      body = @state_processor.process(cmd)
    rescue => e
      [500, {:content_type => "text/html" }, [e, e.backtrace].to_s ]
    else
      [200, {:content_type => "text/html" }, body]
    end
  end

end

