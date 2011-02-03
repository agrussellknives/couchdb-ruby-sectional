module StateProcessor
  module StateProcessorExceptions
    class StateProcessorError < StandardError; end
    class StateProcessorNotFound < StateProcessorError; end
    class StateProcessorConflictError < StateProcessorError; end
    class StateProcessorExit < StateProcessorError; end
    class StateProcessorDoesNotRespond < StateProcessorError; end
    class StateProcessorCannotPerformAction < StateProcessorError; end
    class StateProcessorInvalidState < StateProcessorError; end
    class StateProcessorContextConflict < StateProcessorError; end
    class StateProcessorCommandsAlreadyDefined < StateProcessorError; end
    class StateProcessorNoProtocol < StateProcessorError; end
    class StateProcessorRecoverableError < StateProcessorError; end
  end

  module StateProcessorMatchConstant
    #Match Constants#
    # we can't use "true" or "false" here because people might want to 
    # match those.  we can't use any english words because people might
    # want to match those.  i think the idea of them want to match
    # :sectional_match is alittle obscure, but hey.  anyway,
    # nobody will EVER want to match these.
    StateProcessorFunction = Class.new(BasicObject)
    StateProcessorMatch = Class.new(BasicObject) 
    StateProcessorNoMatch = Class.new(BasicObject) 
    StateProcessorConsume = Class.new(BasicObject) 
  end
end
