require_relative 'helpers'


class ErrorHandler
  include StateProcessor
  include StateProcessorWorker

  class RecoverableError < StateProcessorRecoverableError

  protocol RubyPassThroughProtocol

  on_error do |e|
    return "got an error #{e}"
  end

  commands do

    on :fatal_error do
      raise SecurityError
    end

    on :no_so_fatal_error do
      raise StandardError
    end

    on :not_fatal_at_all_error do
      raise RecoverableError
    end
  end
end

describe 


