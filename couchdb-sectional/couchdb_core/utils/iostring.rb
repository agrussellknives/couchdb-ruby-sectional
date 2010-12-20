require 'forwardable'
require_relative './aspects'


class IOString < IO
  extend Forwardable
  def_delegators(:@read, :each, :each_line, :each_byte, :eof, :eof?, :getc, :gets,
                  :lineno, :close_read, :pos, :tell, :read, :read_nonblock, :readbytes,
                  :readchar, :readline, :readpartial, :scanf, :sysread, :closed_read?)
  def_delegators(:@write, :flush, :fsync, :lineno=, :close_write, :pos=, :print, :<<,
                  :printf, :putc, :puts, :rewind, :syswrite, :write, :write_nonblock,
                  :closed_write?)


  Module.define_aspect :overflow_read_check do |method_name, original_method|
    lambda do |*args, &blk|
      res = ''
      rd_ln = args[0]
      res << original_method.bind(self).call(*args,&blk)
      amt = empty_overflow  #always do this at least once if necessary
      while res.length < rd_ln and (amt and amt > 0)
        args[0] = amt
        res << original_method.bind(self).call(*args,&blk)
        empty_overflow #and as many more times as we need
      end
      res 
    end
  end

  Module.define_aspect :overflow_write_check do |method_name, original_method|
    lambda do |*args, &blk|
      args[0] = args[0].to_s
      len = args[0].length
      begin
        suc = original_method.bind(self).call(*args,&blk)
        if suc < len
          raise Errno::EAGAIN
        end
        @overflow = @overflow[suc..-1] || '' #overflow should always be a string
      rescue Errno::EAGAIN
        @overflow = args[0][suc..-1]
      end
    end
  end

  Module.define_aspect :overflow_close_check do |method_name, original_method|
    lambda do |*args, &blk|
      raise OverflowError if overflowed?
      original_method.bind(self).call(*args,&blk)
    end
  end

  add_overflow_read_check(:getc, :gets, :read, :read_nonblock, :readbytes, :readchar, :readline,
    :readpartial, :scanf, :sysread)

  add_overflow_write_check(:print, :<<, :printf, :putc, :puts, :syswrite, :write, :write_nonblock)
  
  add_overflow_close_check(:close_write, :close_read)


  MAP_METHOD = [:fcntl, :seek, :ioctl, :close, :reopen, :seek, :status, :sync, :sync=, :sysseek]

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

  def read_all(limit=nil)
    str = ''
    rl = (limit and limit > 0) ? limit : SystemSizeLimit
    begin
      loop do
        debugger
        p_str = read_nonblock(rl)
        break if p_str == "\0"
        str << p_str
      end
    rescue Errno::EINTR
      retry
    rescue Errno::EAGAIN, EOFError
      str 
    end
    limit ? str[0..limit] : str
  end

  def truncate p
    if p < 0
      left = read_all
    end
    str = read_all(p)
    raise IOError, "Writing side closed." if @write.closed?
    @write.write n   
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
    debugger if init.length > SystemSizeLimit
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
end 


