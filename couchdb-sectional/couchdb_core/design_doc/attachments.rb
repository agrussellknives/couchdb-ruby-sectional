class DesignDocumentBase
  class Attachments
    @@fm = FileMagic.mime
    
    ATTACHMENT_DIRECTORIES = ['attachments','_attachments']
    
    def initialize &block
      @filenames = {}
      # use instance_eval here since this generally
      # gets called in a ddoc closure
      instance_eval &block if block_given?
      # look in the attachments directory here
      fn = []
      ATTACHMENT_DIRECTORIES.each do |ad|
        if Dir.exists? ad
          Find.find("#{Dir.pwd}/#{ad}") do |entry|
            fn << entry if File.file? entry
          end
        end
      end
      fn.map do |f|
        filename f
      end
      self
    end

    def attachments stub=false
      return @filenames unless stub
      fns = @filenames
      # done this way so we return a new hash, and
      # don't accidentally destroy the attachments
      # hash
      fns.inject({}) do |stubs,(k,v)|
        stubs[k] = v.keys.inject({}) do |file,o|
          if o == :data
            file[:stub] = true
            file[:length] = Base64.decode64(v[o]).length
          else
            file[o] = v[o] 
          end
          file
        end
        stubs
      end
    end

    def filenames 
      @filenames.keys 
    end

    def filename fn
      cwd = Dir.pwd.split(File::Separator).last
      file = File.absolute_path(fn)
      meta = if block_given? then yield else {} end
      if not File.exists? file and not meta.has_key? :data
        raise AttachmentError, "Attachment #{fn} does not exist, and there is no inline data."
      else
        unless meta.has_key? :data
          data = File.read(file)
          meta[:data] = Base64.encode64(data)
          meta[:content_type] = @@fm.file(file) unless meta.has_key? :content_type
          comps = file.split(File::Separator)
          file = comps.last if cwd == comps[-2] or ATTACHMENT_DIRECTORIES.include? comps[-2]
        else
          # use the provided filename for inline attachments
          file = fn
        end
      end
      @filenames[file] = meta
      return file
    end
  end
end
