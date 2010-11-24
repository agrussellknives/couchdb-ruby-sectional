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

  module StateProcessorMatchConstant
    #Match Constants#
    # we can't use "true" or "false" here because people might want to 
    # match those.  we can't use any english words because people might
    # want to match those.  i think the idea of them want to match
    # :sectional_match is alittle obscure, but hey.  anyway,
    # nobody will EVER want to match these.
    STATE_PROCESSOR_MATCH= :'f525cd74-8591-4ddb-a8e3-909c3f661ad0'
    STATE_PROCESSOR_NOMATCH = :'e963cfaa-f044-4e86-907e-7a2bcc63ed3a' 
    STATE_PROCESSOR_CONSUME= :'d1fcd65a-4d35-498a-8b12-0e6b7d9cc851'
  end
end
