require_relative 'thin_adapter'
require 'rack'

module SectionMethods
  extend ActiveSupport::Concern 

  module ClassMethods
    def section klass, &block
      begin
        section_klass = const_get("#{self}::#{klass}",false)
      rescue NameError
        section_klass = Class.new(Section)
        section_klass.instance_eval &block
        section_klass = const_set(klass, section_klass)
      end
    end

    def template kind = nil
      @@template ||= {}
      kind ||= :default
      if block_given?
        @@template[kind] = yield
      else
        @@template[kind] = kind.to_s
      end
    end
  end
  
  def template kind = nil
    kind ||= :default
    @@template[kind]
  end

  def default
    with :default
  end

  def with kind = nil
    nesteds = self.nesting
    # assemble each template above us
    nesteds.each do |n|
      n = n.template(kind)
    end
  end
    
end

module SectionMethods
  extend ActiveSupport::Concern 

  module ClassMethods
    def section klass, &block
      begin
        section_klass = const_get("#{self}::#{klass}",false)
      rescue NameError
        section_klass = Class.new(Section)
        section_klass.instance_eval &block
        section_klass = const_set(klass, section_klass)
      end
    end

    def template kind = nil
      @@template ||= {}
      kind ||= :default
      if block_given?
        @@template[kind] = yield
      else
        @@template[kind] = kind.to_s
      end
    end
  end
  
  def template kind = nil
    kind ||= :default
    @@template[kind]
  end
  alias :with :template
end
 


class Section
  include StateProcessor
  include StateProcessorWorker
  include SectionMethods
end

class SectionalApp
  include StateProcessor
  include StateProcessorWorker
  include SectionalHTTPApplication
  include SectionMethods
 
  define_method :worker_init, instance_method(:initialize)
  
  attr_accessor :last_access

  def initialize
    worker_init
    @state_processor_class = StateProcessor[self.class]
    @state_processor_class.protocol = HTTPApplication
    #TODO - put this in couch so the sessions don't
    # die with the server / we might want to figure out
    # a way to serialize them, or at least remember where they are.
    @state_processor_bag = {}
  end

  class Error404 < RuntimeError; end

end
