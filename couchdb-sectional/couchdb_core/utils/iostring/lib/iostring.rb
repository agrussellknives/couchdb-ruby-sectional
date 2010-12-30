require 'forwardable'
require 'dl'

require_relative '../../aspects' 
require_relative '../iostring.bundle'


class IOString < IO 
  include TiedWriter
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
      if args[0].length > SystemSizeLimit
        @overflow = args[0].dup
        args[0] = args[0][0..(SystemSizeLimit-1)]
      end
      begin
        @callno += 1
        suc = @write.send(method_name, *args, &blk)
        @total_read += suc
        #overflow is basically our internal buffer
        #shift off th number of successfully written characters
        @overflow = @overflow[suc..-1] || ''
        STDOUT << "#{['ok', @total_length, @total_read, suc, @callno, @overflow.length]}\n"
      rescue => e
        STDOUT << "#{['fail',@total_length, @total_read, suc, @callno, @overflow.length]}\n"
        raise
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

  define_aspect :byte_wise_overflow_check do |method_name, original_method|
    lambda do |*args, &blk|
      res = original_method.bind(self).call(*args,&blk)
      if overflowed?
        c, @overflow = @overflow.chr, @overflow[1..-1]
        begin 
          @write.putc c 
        rescue => e
          debugger; 1
        end
      end
      res
    end
  end

  add_overflow_read_check(:getc, :gets, :read, :read_nonblock, :readchar, :readlines, :readline,
    :readpartial)

  add_overflow_write_check(:print, :<<, :printf, :putc, :puts, :write, :write_nonblock)

  # sync to a readpipe makes no sense...
  extend Forwardable
  def_delegators :@write, :sync, :sync=, :closed_write?, :syswrite
  def_delegators :@read, :eof?, :closed_read?, :each_byte, :getbyte, :readbyte, :sysread, :each_char

  add_byte_wise_overflow_check(:getbyte,:readbyte,:each_byte, :each_char)

  UNDEF_METHOD = [:ungetbyte, :ungetc, :fileno]

  UNDEF_METHOD.each do |meth|
    undef_method meth
  end

  MAP_METHOD = [:fcntl, :ioctl, :close, :status, :set_encoding]

  MAP_METHOD.each do |meth|
    define_method meth do |*args|
      @ios.collect { |i| i.send meth, *args}
    end
  end

  SystemSizeLimit = 2**16 
  
  class OverflowError < IOError; end

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

  def closed_read?
    @read.closed?
  end

  def closed_write?
    @write.closed?
  end

  [:external, :internal].each do |t|
    meth_name = "#{t}_encoding".to_sym
    define_method meth_name do 
      encs = @ios.collect { |i| i.send meth_name }
      if encs.uniq!
        encs[0]
      else
        raise EncodingError, "The #{t} encodings differ for ends of IOSTring"
      end
    end
  end

  def initialize_copy obj
    # i guess this was already done up stream, since it seems to work
    self
  end

  alias :old_reopen :reopen
  def reopen(io, mode_str = nil)
    raise IOError, "can't set mode on an IOSTring" if mode_str
    if io.is_a? IOString
      @write, @read = io.instance_eval { @ios }
    elsif io.is_a? String
      read_all
      write io
    else
      raise IOError, "cannot reopen IOString without a string or other IOString"
    end
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

  def initialize init=nil
    @read, @write = IO.pipe
    @total_length = init.length
    @callno = 0
    @total_read = 0
    # this is sort of hacky, but everything now gets inited correctly
    super(@read.fileno)
    self.write_io = @write
    @overflow = ''
    write init if init
    @ios = [@write,@read]
    # set up our encodings
    enc = "#{Encoding.default_external.name}"
    enc << ":#{Encoding.default_internal.name}" if Encoding.default_internal
    @ios.map do |i|
      i.set_encoding(enc)
    end
    @overflow_mutex = Mutex.new
    self
  end

  def readchars(chars)
    res = ''
    chars.times do
      res << readchar 
    end
    res
  end
    
  def overflowed?
    @overflow.size > 0
  end
  
  def empty_overflow
    if overflowed? then write_nonblock @overflow else 0 end
  end

  def to_s
    raise OverflowError if overflowed?
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
      rescue Errno::EBADF => e
        warn "Got an error #{e} trying to close #{i}"
        #okay, i probably don't care
      end
    end
    nil
  end

  def each
    Enumerator.new do |y|
      while r = gets
        y << r
      end
    end
  end

  def isatty
    false
  end
  alias :tty? :isatty

  def to_io
    @read
  end

  def closed?
    c = @ios.collect { |i| i.closed? }
    c.include? false ? false : true
  end

  def fsync
    raise Errno::EINVAL, "can't fsync pipes"
  end

  #add_logging(*instance_methods.to_a)
end 


