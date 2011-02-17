class DesignDocumentBase
  class View
    private_class_method :new
    class << self
      def const_missing const
        # only enable lookups in the view library
        puts "#{const} missing"
      end
    end
    # set these up with negative arity so that we can
    # throw an error if we don't override them
    def map *args 
      raise AbstractClassInstantionError, "Cannot run abstract view"
    end

    def reduce *args 
      raise AbstractClassInstantionError, "Cannot use abstrace reduce"
    end
  end
end
