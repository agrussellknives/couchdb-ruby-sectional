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
      
      result = original_method.bind(self).call(*args, &blk)
      res = res << result rescue result
      amt = empty_overflow  #always do this at least once if necessary
      
      # if the result was nil, go ahead and return that
      return nil unless res
      
      while res.length < rd_ln and amt > 0
        args[0] = amt
        res << original_method.bind(self).call(*args, &blk)
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
        # the only methods that return nil are the ones that write
        # one character, so if it returns nil, replace it with one
        suc = original_method.bind(self).call(*args, &blk) || 1 # don't let it go nil
        #overflow is basically our internal buffer
        #shift off th number of successfully written characters
        @overflow = @overflow[suc..-1] || ''
      rescue => e
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
  #extend Forwardable
  #def_delegators :@write, :sync, :sync=, :closed_write?, :syswrite
  #def_delegators :@read, :eof?, :closed_read?, :each_byte, :getbyte, :readbyte, :sysread, :each_char

  #add_byte_wise_overflow_check(:getbyte,:readbyte,:each_byte, :each_char)

  UNDEF_METHOD = [:ungetbyte, :ungetc]

  UNDEF_METHOD.each do |meth|
    undef_method meth
  end


   #MAP_METHOD.each do |meth|
   #  define_method meth do |*args|
   #    ios.collect { |i| i.send meth, *args}
   #  end
   #end

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
  
  def fcntl(*args)
    [write_io.fcntl(*args),super(*args)]
  end

  def binmode
    nil
  end

  [:external, :internal].each do |t|
    meth_name = "#{t}_encoding".to_sym
    define_method meth_name do 
      encs = ios.collect { |i| i.send meth_name }
      if encs.uniq!
        encs[0]
      else
        raise EncodingError, "The #{t} encodings differ for ends of IOSTring"
      end
    end
  end

  # add them to this instance, and not to the superclass
  add_overflow_close_check(:close_write, :close_read, :close)

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

  def initialize_copy obj
    # i guess this was already done up stream, since it seems to work
    debugger;1
    self.reopen(obj.fileno)
    self.write_io = obj.write_io 
    self
  end

  def initialize init=nil
    read, write = IO.pipe
    # this is sort of hacky, but everything now gets inited correctly
    super(read.fileno)
    self.write_io = write
    @overflow = ''
    write init if init
    # set up our encodings
    enc = "#{Encoding.default_external.name}"
    enc << ":#{Encoding.default_internal.name}" if Encoding.default_internal
    set_encoding(enc)
    self
  end

  def ios
    [self, self.write_io]
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
    if write_io.closed?
      str = read
    else
      str = read_all
      write str
    end
    str
  end
  alias :value :to_s
  alias :string :to_s

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

  def closed?
    [closed_read?, closed_write?].include? false ? false : true
  end

  def fsync
    raise Errno::EINVAL, "can't fsync pipes"
  end
  #add_logging(*instance_methods.to_a)
end 


