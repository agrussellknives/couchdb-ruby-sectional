class DesignDocumentBase
  class Rewrites
    class Rewrite
      def initialize &block 
        raise ArgumentError, "Block required to rewrite" unless block_given?
        @rewrite = {}
        instance_eval &block
      end
      def from frm
        @rewrite[:from] = frm
      end
      def to t
        @rewrite[:to] = t
      end
      def method meth
        #normalize method symbol
        # yeah... downcase..
        meth = meth.to_s.downcase.intern
        raise ArgumentError, "Unrecognized HTTP verb #{meth}" unless [:get, :put, :head, :post, :delete].include? meth
        @rewrite[:method] = meth
      end
      def query quer
        raise ArgumentError, "Query rewrite should be a Hash" unless quer.is_a? Hash
        @rewrite[:query] = quer
      end
      
      def to_hash
        @rewrite
      end
      
      def to_s
        @rewrite.to_s
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
