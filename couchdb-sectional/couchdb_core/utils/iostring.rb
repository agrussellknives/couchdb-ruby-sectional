require 'forwardable'
require_relative './aspects'


class IOString < IO
  #extend Forwardable
  #def_delegators(:@read, :each, :each_line, :each_byte, :eof, :eof?, :getc, :gets,
  #                :lineno, :close_read, :pos, :tell, :read, :read_nonblock, :readbytes,
  #                :readchar, :readline, :readpartial, :scanf, :sysread, :closed_read?)
  #def_delegators(:@write, :flush, :fsync, :lineno=, :close_write, :pos=, :print, :<<,
  #                :printf, :putc, :puts, :rewind, :syswrite, :write, :write_nonblock,
  #                :closed_write?)
  #


  define_aspect :overflow_read_check do |method_name, original_method|
    lambda do |*args, &blk|
      begin
        STDERR << "overflow read check for #{method_name}\n"
        res = ''
        rd_ln = args[0] || SystemSizeLimit
        args[0] = rd_ln
        #res << original_method.bind(self).call(*args,&blk)
        #res << @read.read_nonblock(*args, &blk)
        res << @read.send(method_name, *args, &blk)
        amt = empty_overflow  #always do this at least once if necessary
        while res.length < rd_ln and (amt and amt > 0)
          args[0] = amt
          #res << original_method.bind(self).call(*args,&blk)
          #res << @read.read_nonblock(*args, &blk)
          res << @read.send(method_name, *args, &blk)
          empty_overflow #and as many more times as we need
        end
        res 
      rescue Errno::EAGAIN => e 
        '' if e.message =~ /read would block/ 
      end
    end
  end

  define_aspect :overflow_write_check do |method_name, original_method|
    lambda do |*args, &blk|
      STDERR << "overflow write check for #{method_name}\n"
      args[0] = args[0].to_s
      args[0] << "\n" if method_name == :puts
      len = args[0].length
      begin
        #suc = original_method.bind(self).call(*args,&blk)
        suc = @write.write_nonblock(*args, &blk) 
        if suc < len
          raise Errno::EAGAIN
        end
        @overflow = @overflow[suc..-1] || '' #overflow should always be a string
      rescue Errno::EAGAIN
        @overflow = args[0][suc..-1]
      end
    end
  end

  define_aspect :overflow_close_check do |method_name, original_method|
    lambda do |*args, &blk|
      STDERR << "overflow close check for #{method_name}\n"
      raise OverflowError if overflowed?
      original_method.bind(self).call(*args,&blk)
    end
  end

  define_aspect :read_seek_check do |method_name, original_method|
    lambda do |*args, &blk|
      STDERR << "read seek check for #{method_name} in position #{@readpos}\n"
      str = original_method.bind(self).call(*args,&blk)
      suffix = str[@readpos..-1]
      @write.write_nonblock (str[0..@readpos-1]) if @readpos > 0
      @readpos = 0
      suffix 
    end
  end

  define_aspect :write_seek_check do |method_name, original_method|
    lambda do |*args, &blk|
      STDERR << "write seek check for #{method_name} in position #{@readpos}\n"
      str = @read.read_nonblock(@readpos) if @readpos > 0
      original_method.bind(self).call(*args, &blk)
      @readpos = 0
    end
  end

  add_overflow_read_check(:getc, :gets, :read, :read_nonblock, :readbyte, :readchar, :readline,
    :readpartial, :sysread)
  add_read_seek_check(:read, :read_nonblock, :readchar, :readline, :getc, :gets, :readpartial, :sysread)

  add_overflow_write_check(:print, :<<, :printf, :putc, :puts, :syswrite, :write, :write_nonblock)
  add_write_seek_check(:print, :<<, :putc, :puts, :syswrite, :write, :write_nonblock) 


  add_overflow_close_check(:close_write, :close_read)


  MAP_METHOD = [:fcntl, :ioctl, :close, :reopen, :status, :sync, :sync=]

  SystemSizeLimit = 2**16 

  class OverflowError < IOError; end

  MAP_METHOD.each do |meth|
    define_method meth do |*args|
      @ios.collect { |i| i.send meth, *args}
    end
  end

  class << self
    def open val
      n = IOString.new(init)
      n.close_write
      res = (yield n if block_given?) or n
      n.close
      res
    end
  end

  def binmode
    nil
  end

  def close_write!
    @write.close
  end

  def close_read!
    @read.close
  end

  def seek n, whence = IO::SEEK_SET
    # this is of questionable semantic value
    if whence == IO::SEEK_CUR or whence == IO::SEEK_END
      @readpos += n
    else 
      @readpos = n
    end
    @readpos
  end

  def rewind
    seek(0)
  end

  def read_all(limit=nil)
    str = ''
    rl = (limit and limit > 0) ? limit : SystemSizeLimit
    begin
      loop do
        p_str = read_nonblock(rl)
        break if p_str == "" 
        str << p_str
      end
    rescue Errno::EINTR
      retry
    rescue Errno::EAGAIN, EOFError
      str 
    end
    limit ? str[0..limit] : str
  end
  private :read_all

  def truncate len=0
    debugger if len < 0
    raise IOError, "Writing side closed." if @write.closed?
    read_reset = true if @readpos > 0
    @readpos = 0 
    left = read_all
    if len > 0 then
      if left.length < len then left << ("\0" * (len - left.length)) end
    end 
    write left[0..len].chop
    if read_reset 
      @readpos = len >= 0 ? len : (left.length + len)
    end
    @readpos
  end
    

  def pid
    nil
  end

  def ungetc c
    @read.write c
  end
  
  def initialize init=nil
    @read, @write = IO.pipe
    @overflow = ''
    @readpos = 0
    write_nonblock init if init
    @ios = [@write,@read]
    self
  end

  def overflowed?
    @overflow.size > 0
  end
  
  def empty_overflow
    write_nonblock @overflow if overflowed?
  end

  def to_s
    raise IOOverflowError if overflowed?
    str = ''
    if @write.closed?
      str = read
    else
      str = read_all
      write str
    end
    str
  end
  alias :value :to_s
  alias :string :to_s

  def close
    @ios.map do |i|
      begin
        i.close
      rescue IOError => e
        raise unless e.message == "closed stream"
      end
    end
    nil
  end

  def isatty
    false
  end
  alias :tty? :isatty

  def fileno
    @ios.collect { |i| i.fileno }
  end
  alias :fileno :to_i

  def closed?
    c = @ios.collect { |i| i.closed? }
    c.include? false ? false : true
  end

  add_logging(*instance_methods.to_a)
end 


