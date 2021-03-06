require 'eventmachine'

module NilProtocol
  include EM::Protocols::LineText2

    def receive_line data
      @run.call(data)
    end

    def send_data data
        $stderr << data
    end

    def run &block
      @run = block
    end

end
