module StateProcessor
  class StateProcessorList
    include StateProcessorExceptions
    
    def initialize
      @processorlist= {}
    end
    
    def lookup state, style = false
      raise ArgumentError unless [false,:class].include? style
      if state.class == Symbol or state.class == String then
        (style == :class) ? state.to_s.camelize : state.to_s.underscore.intern  
      elsif state.class == Class then
        (style == :class) ? state.to_s : state.to_s.underscore.split('/').last.intern  
      end
    end

    def knows_state? state
      @processorlist.has_key?(lookup(state))
    end

    def << state
      @processorlist[lookup(state)] = state
    end
       
    def [] state
      if knows_state? state
        @processorlist[lookup(state)]
      else
        raise StateProcessorInvalidState, "No Processor is defined for #{state}"
      end
    end

  end
end
