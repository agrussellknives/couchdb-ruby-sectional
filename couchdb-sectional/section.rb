require_relative 'thin_adapter'

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
  protocol HTTPApplication
  include SectionalHTTPApplication
  include SectionMethods
  
  class Error404 < Exception; end
end
