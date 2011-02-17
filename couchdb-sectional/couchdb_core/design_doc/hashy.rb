#It's sorta like open struct, but you init it DSL style.
#hashy do
#  allowed_meta "whatever"
#  allowed_meta2 "also whatever"
#end
#

require 'delegate'

class Hashy < SimpleDelegator
  class << self
    def allowed_meta *meta
      @allowed_meta ||= []
      @allowed_meta.push(meta).flatten!  #take that!
      
      @allowed_meta.each do |meta|
        meta = meta.to_s.underscore.intern
        self.send :define_method, meta do |arg = nil|
          return @_hash_intern[meta] unless arg
          @_hash_intern[meta] = arg
        end
      end
    end
  end
  
  def initialize obj = {}, &block
    raise ArgumentError "Block required for #{self.class}" unless block_given?
    super
    @_hash_intern = obj
    instance_eval &block
  end

  def to_hash
    @_hash_intern
  end

  def to_s
    @_hash_intern.to_s
  end
end

  
