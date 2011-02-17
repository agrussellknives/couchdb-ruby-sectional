class DesignDocumentBase
  class Rewrites
    class Rewrite < Hashy

      allowed_meta [:from, :to, :method, :query]

      alias_method :orig_method, :method
      def method meth
        meth = meth.to_s.downcase.intern
        raise ArgumentError, "Unrecognized HTTP verb #{meth}" unless [:get, :put, :head, :post, :delete].include? meth
        orig_method meth 
      end

    end

    def initialize &block
      raise ArgumentError, "Block required for rewrites" unless block_given?
      @rewrites = [] 
      instance_eval &block
      self 
    end
    
    def rewrite &block
      @rewrites << Rewrite.new(&block)
    end

    def to_a
      @rewrites.collect { |r| r.to_hash }
    end

    def to_s 
      @rewrites.collect { |r| r.to_s }.to_s
    end
  end
end
