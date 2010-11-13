module StateProcessor
  module StateProcessorExceptions
    class StateProcessorError < StandardError; end
    class StateProcessorConflictError < StateProcessorError; end
    class StateProcessorExit < StateProcessorError; end
    class StateProcessorDoesNotRespond < StateProcessorError; end
    class StateProcessorCannotPerformAction < StateProcessorError; end
    class StateProcessorInvalidState < StateProcessorError; end
    class StateProcessorContextConflict < StateProcessorError; end
  end
end
