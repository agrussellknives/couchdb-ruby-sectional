require 'thin'
require_relative 'eval_debugger'
require_relative 'state_processor'

module SectionalHTTPApplication 
  def call(env)   
    cmd = env['REQUEST_PATH'].split('/').collect do |pc|
      pc.to_sym
    end
    body = process(cmd)
    [200,{ :content_type => text/plain}, body]
  end
end

module HTTPApplication
  # this doesn't actually do anything, since we leverage
  # thin's HTTP EM protocol, but we need it just to let
  # our section know what protocol it's in
end
