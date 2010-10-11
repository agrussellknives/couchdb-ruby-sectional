module Kernel
  def debugger(steps = 1, &block)
    if $0.include? 'couchdb_view_server' then
      $realstdout = $stdout unless $realstdout
      $realstdout.puts ["log","Waiting for debugger..."].to_json
    else
      $stderr.puts "Waiting for debugger..."
    end
    
    Debugger.wait_connection = true
    Debugger.start_remote
    if block
      Debugger.start({}, &block)
    else
      Debugger.start
      Debugger.run_init_script(StringIO.new)
      if 0 == steps
        Debugger.current_context.stop_frame = 0
      else
        Debugger.current_context.stop_next = steps
      end
    end
  end
  alias breakpoint debugger unless respond_to?(:breakpoint)
end


module Debugger
  # Implements debugger "list" command, listing evaled strings.
  
  class CommandProcessor::State
    attr_accessor :original_file
  end
  
  class ListCommand < Command

    alias :std_execute :execute
      
    def execute
      listsize = Command.settings[:listsize]
      # if our file is an eval, check if we're closed around the string that created us.
      # if so, write it to a temp file, and reset state so that we list that file.
      if /\(eval\)/ =~ @state.file
        @state.original_file = @state.file
        locals = eval "local_variables", Debugger.current_context.frame_binding(0)
        if locals.include?(:string)
          string,fname = eval "[string,\"/tmp/eval-#{string.object_id}.rb\"]", Debugger.current_context.frame_binding(0)
          File.open(fname,'w') do |f|
            f.write(string)
          end
          @state.file = fname
        end
        
      end
      #call original method
      std_execute
      
      #restore the state incase anybody else wants it for something
      if @state.original_file
        File.file?(@state.file)
        File.delete(@state.file)
        @state.file = @state.original_file
      end
    end

    class << self

      def help(cmd)
        %{
          l[ist]\t\tlist forward
          l[ist] -\tlist backward
          l[ist] =\tlist current line
          l[ist] nn-mm\tlist given lines
          * This is a patched debugger that will list the string 
          * used to create an evaled proc if the proc was closed
          * around the string and it was called "string"
          * NOTE - to turn on autolist, use 'set autolist'
        }
      end
    end

    private

    # Show FILE from line B to E where CURRENT is the current line number.
    # If we can show from B to E then we return B, otherwise we return the
    # previous line @state.previous_line.
    def display_list(b, e, file, current)
      lines = LineCache::getlines(file, Command.settings[:reload_source_on_change])
      b = [b,1].max
      e = lines.size if lines.size < e
      print "[%d, %d] in %s\n", b, e, file

      if lines
        return @state.previous_line if b >= lines.size
        b.upto(e) do |n|
          if n > 0 && lines[n-1]
            if n == current
              print "=> %d  %s\n", n, lines[n-1].chomp
            else
              print "   %d  %s\n", n, lines[n-1].chomp
            end
          end
        end
      else
        errmsg "No sourcefile available for %s\n", file
        return @state.previous_line
      end
      return e == lines.size ? @state.previous_line : b
    end
  end
end
