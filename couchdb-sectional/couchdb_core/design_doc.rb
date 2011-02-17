require 'base64'
require 'filemagic'
require 'find'
require 'set'

require 'active_support/concern'

require 'ruby-debug'

require 'ripper2ruby'
require 'ripper'

require_relative "utils/class_nesting"

require_relative "design_doc/hashy"
require_relative "design_doc/exceptions"
require_relative "design_doc/rewrites"
require_relative "design_doc/attachments"
require_relative "design_doc/view"

 
class DesignDocumentBase
  # make it hard to instatiate the base 
  private_class_method :new

  SECTIONS = [:shows, :lists, :filters, :updates]

  class << self

    def inherited sub
      sub.instance_eval do
        @id = sub.to_s.underscore.intern
        @attachments = nil
        @rewrites = nil
        @rev = nil
      end
    end
  
    def id idv=nil
      if idv then @id = "_design/#{idv}" else @id end
    end

    def rev revv = nil
      if revv then @rev = revv else @rev end
    end

    def language
      return :ruby
    end

    def attachments full=false, &block
      if block_given?
        @attachments = Attachments.new &block
      else
        case full
          when false, :names, :filenames then @attachments.filenames
          when :stub then @attachments.attachments :stub 
          when true, :full then @attachments.attachments 
        end
      end
    end

    def views
      self.constants.inject [] do |views, const|
        view = self.const_get const
        views << view if view.is_a? Class and view.superclass == DesignDocumentBase::View
        views
      end
    end

    #define section functions
    SECTIONS.each do |section|
      mod = section.to_s.camelcase.intern #bah
      define_method section do
        begin
          the_mod = self.const_get mod 
          the_mod.instance_methods
        rescue NameError
          nil
        end
      end
    end

    def rewrites &block
      if block_given? 
        @rewrites = Rewrites.new &block
      else
        @rewrites.to_a rescue nil
      end
    end

    def to_json
      json_hash = {}
      #rewrites is an array... 
      json_hash[:rewrite] = rewrites
      # we'll do inline attachments first
      # i pretty well know this works, so just comment it out while debugging
      #json_hash[:attachments] = attachments :full
      #
      imported_files = Set.new

      SECTIONS.each do |section|
        methods = self.send(section)
        methods and methods.each do |method|
          src = const_get(section.to_s.camelize.intern).instance_method(method).source_location
          next if imported_files.include? src[0]
          imported_files << src[0]
        end 
      end
      
      views and views.each do |view|
        [:map, :reduce].each do |fun|
          src = view.instance_method(fun).source_location
          next if imported_files.include? src[0]
          imported_files << src[0]
        end
      end

      sexps = Set.new
      sexps = imported_files.collect do |f|
        Ripper.sexp(File.open(f))
      end

      debugger;1

      
    end
  end
end


