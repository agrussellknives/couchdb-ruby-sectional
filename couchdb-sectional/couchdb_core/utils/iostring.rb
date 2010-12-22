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
      if [:gets, :readlines].include? method_name then
        if args[0].is_a? Integer
          rd_ln = args[0]
        else
          rd_ln = SystemSizeLimit 
        end
      else
        rd_ln =  args[0] || SystemSizeLimit
      end
      res, amt = ['', 0]
      
      result = @read.send(method_name, *args, &blk)
      res = res << result rescue result
     
      amt = empty_overflow  #always do this at least once if necessary
      
      # if the result was nil, go ahead and return that
      return nil unless res

      while res.length < rd_ln and amt > 0
        args[0] = amt
        res << @read.send(method_name, *args, &blk)
        amt = empty_overflow #and as many more times as we need
        break if not res # if we've read nil, then we're done.
      end
      res 
    end
  end

  define_aspect :overflow_write_check do |method_name, original_method|
    lambda do |*args, &blk|
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
      suc
    end
  end

  define_aspect :overflow_close_check do |method_name, original_method|
    lambda do |*args, &blk|
      raise OverflowError if overflowed?
      original_method.bind(self).call(*args,&blk)
    end
  end

  add_overflow_read_check(:getc, :gets, :read, :read_nonblock, :readbyte, :readchar, :readlines, :readline,
    :readpartial, :sysread)

  add_overflow_write_check(:print, :<<, :printf, :putc, :puts, :syswrite, :write, :write_nonblock)

  # sync to a readpipe makes no sense...
  extend Forwardable
  def_delegators :@write, :sync, :sync=


  MAP_METHOD = [:fcntl, :ioctl, :close, :reopen, :status]

  SystemSizeLimit = 2**16 

  class OverflowError < IOError; end

  MAP_METHOD.each do |meth|
    define_method meth do |*args|
      @ios.collect { |i| i.send meth, *args}
    end
  end

  class << self
    def open val
      n = IOString.new(val)
      res = (yield n if block_given?) or n
      n.close
      res
    end
  end

  def binmode
    nil
  end

  def close_write
    @write.close
  end

  def close_read
    @read.close
  end
  
  # add them to this instance, and not to the superclass
  add_overflow_close_check(:close_write, :close_read)

  def seek
    raise Errno::ESPIPE, "Invalid Seek" 
  end

  def read_all(limit=nil)
    str = ''
    rl = (limit and limit > 0) ? limit : SystemSizeLimit
    begin
      loop do
        p_str = read_nonblock(rl)
        break if p_str == "" || p_str.nil?
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


  def pid
    nil
  end

  def ungetc c
    @read.write c
  end
  
  def initialize init=nil
    @read, @write = IO.pipe
    @overflow = ''
    write init if init
    @ios = [@write,@read]
    self
  end

  def overflowed?
    @overflow.size > 0
  end
  
  def empty_overflow
    if overflowed? then write @overflow else 0 end
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

  def fsync
    raise Errno::EINVAL, "can't fsync pipes"
  end

  #add_logging(*instance_methods.to_a)
end 


