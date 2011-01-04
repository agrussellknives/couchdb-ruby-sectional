require_relative '../couchdb-sectional/couchdb_core/utils/iostring'
require 'timeout'
require 'tempfile'
require 'rspec'

describe "IOString should work almost exactly like StringIO" do

  before :each do
    @io = IOString.new("")
  end

  after :each do
    begin
      #okay
    ensure
      @io.close rescue nil
      @io = nil
    end
  end

  it "should write" do
    # mode tests don't make much sense here, since it's open both ways
    # perhaps we add this later
    f = IOString.new("")
    f.print("foo")
    f.string.should == "foo"
  end

  it "should init with value" do
    f = IOString.new("foo")
    f.string.should == "foo"
    f.print "foo"
    f.string.should == "foofoo"
  end

  it "getting the string should not clear the string" do
    @io.write "foo"
    @io.string.should == "foo"
    @io.write "bar"
    @io.string.should == "foobar"
  end

  it "reading the string SHOULD clear the string" do
    @io.write "foo"
    @io.read_nonblock(1000).should == "foo"
    @io.write "bar"
    @io.read_nonblock(1000).should == "bar"
  end

  describe "handles large strings" do
    it "should be totally seamless if it's less than the system limit", collision:true do
      f = IOString.new("a" * (IOString::SystemSizeLimit - 10))
      f.string.should == "a" * (IOString::SystemSizeLimit - 10)
      f.close
      f = nil
      GC.start
      sleep 1
    end

    it "requires an overflow check if it's more than the system limit", collision:true do
      f = IOString.new("a" * (IOString::SystemSizeLimit) + ("b" * 10000))
      lambda { f.close_write }.should raise_error(IOString::OverflowError)
      str = f.read(IOString::SystemSizeLimit)
      f.close_write
      # otherwise the call blocks
      str << f.read(10000)
      str.should == "a" * (IOString::SystemSizeLimit) + ("b" * 10000)
      f.close
      f = nil
      GC.start
      sleep 1
    end

    it "not subject to system limit read", collision:true do
      g = IOString.new("a" * (2**20))
      str = g.read_nonblock(2**20)
      str.should == "a" * (2**20)
      g.close
    end
  end
    
  it "shouldn't overwrite" do
    responses = ['', 'just another ruby', 'hacker']
    responses.each do |resp|
      @io.puts(resp)
    end
    @io.read_nonblock(1000).should == "\njust another ruby\nhacker\n"
  end

  describe "gets" do

    it "should gets" do
      IOString.new("\n").gets.should == "\n"
      IOString.new("a\n").gets.should == "a\n"
      IOString.new("a\nb\n").gets.should == "a\n"
      IOString.new("a\nb").gets.should == "a\n"
      IOString.new("abc\n\ndef\n").gets.should == "abc\n"
      IOString.new("abc\n\ndef\n").gets("").should == "abc\n\n"
    end

    it "nil seps is a blocking call" do
      f = IOString.new("abc\n\ndef\n")
      res = ''
      t = Thread.new do
        res = f.gets(nil)
      end
      lambda do
        timeout(1) do
        end
      end.should raise_error Timeout::Error
      f.close_write
      t.join
      res.should == "abc\n\ndef\n"
    end

    it "should block waiting for newlines" do
      lambda do 
        timeout(1) do
          IOString.new("").gets
        end
      end.should raise_error(Timeout::Error)
    
      lambda do
        timeout(1) do
          IOString.new("a").gets
        end
      end.should raise_error(Timeout::Error)
    end

    it "should sep other chars" do
      f = IOString.new("a|b|c|")
      ar = []
      3.times do
        ar << f.gets('|')
      end
      ar.should == ["a|","b|","c|"]

      f = IOString.new("foo\nbar\nbaz\n")
      f.gets(2).should == "fo"

      o = Object.new
      def o.to_str
        "z"
      end
      f.gets(o).should == "o\nbar\nbaz"

      f = IOString.new("foo\nbar\nbaz\n")
      f.gets("az").should == "foo\nbar\nbaz"
      f = IOString.new("a" * 10000 + "zz")
      f.gets("zz").should == "a" * 10000 + "zz"
      f = IOString.new("a" * 10 + "zz!")
      
      res = ''
      t = Thread.new do
        res = f.gets("zzz")
      end

      # make sure it blocks 
      lambda do
        timeout(1) do
          t.join
        end
      end.should raise_error Timeout::Error
     
      # until it receieve a sep
      f.puts "zzz"
      t.join # wait for it to finish

      res.should == "a" * 10 + "zz!zzz"
    end
  end

  describe "readlines" do
    it "should timeout without newlines" do
      lambda do 
        timeout(1) do
          IOString.new("").readlines
        end
      end.should raise_error Timeout::Error

      lambda do
        timeout(1) do
          IOString.new("a").readlines
        end
      end.should raise_error Timeout::Error
    end
    
    it "should read multiple lines into an array" do
      ts = ["\n","a\n","a\nb\n"]
      ts.each do |s|
        f = nil
        t = Thread.new do
          f = IOString.new(s)
        end
        t.join(0.1)
        f.close_write
        f.readlines 
      end
    end

    it "should readlines with whatever seperator" do
      tl = lambda do |s, sep = $/|
        f = nil
        t = Thread.new do
          f = IOString.new(s)
        end
        t.join(0.1)
        f.close_write
        f.readlines(sep)
      end

      tl.call("a\nb").should == ["a\n","b"]
      tl.call("abc\n\ndef\n").should == ["abc\n", "\n", "def\n"]  
      tl.call("abc\n\ndef\n",nil).should == ["abc\n\ndef\n"]  
      tl.call("abc\n\ndef\n","").should == ["abc\n\n", "def\n"]  
    end

    it "should readlines with a limit" do
      t = Thread.new do
        @io.write("foobar\n" * 10)
      end
      t.join(0.1)
      @io.close_write
      @io.readlines(5).should == ["fooba","r\n"].cycle(10).to_a
    end
  end

  it "should write nonblocking" do
    # this needs a better test to make sure it's actually a nonblocking
    # write
    f = IOString.new("f")
    f.write_nonblock("foo")
    f.string.should == "ffoo"
  end

  it "should open with a value" do
    # this usage really makes no sense
    res = IOString.open("foo") do |f|
      f.read_nonblock(5)
    end
    res.should == "foo"
  end

  it "should not be a tty" do
    IOString.new("").isatty.should == false
  end

  it "should fsync on call" do
    lambda { IOString.new("blah blah blah").fsync }.should raise_error Errno::EINVAL
  end

  it "should set sync on call" do
    IOString.new("foo").sync.should == true
    t = IOString.new("").sync = false
    t.should == false
  end

  it "should fcntl on each io element" do
    @io.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
    fct = @io.fcntl(Fcntl::F_GETFL,0)
    fct.should == [Fcntl::O_NONBLOCK | Fcntl::O_WRONLY, Fcntl::O_NONBLOCK | Fcntl::O_RDONLY]
    # perhaps i should coalcse these into a single element so it seems more correct?
  end

  it "should close both" do
    @io.close 
    lambda { @io.puts "no"}.should raise_error(IOError)
    lambda { @io.gets}.should raise_error(IOError)
  end

  it "should close for reading" do
    @io.write "hello"
    @io.close_read
    lambda { @io.read }.should raise_error(IOError)
    lambda { @io.close_read }.should raise_error(IOError)
    lambda { @io.write "world" }.should_not raise_error(IOError)
  end

  it "should close for writing" do
    @io.write "foo"
    @io.close_write
    lambda { @io.read }.call.should == "foo"
    lambda { @io.write "bar"}.should raise_error(IOError)
    lambda { @io.close_write }.should raise_error(IOError)
  end

  it "should return the correct closed" do
    @io.closed_read?.should == false 
    @io.closed_write?.should == false
    @io.closed? == false
    debugger
    @io.close_read
    @io.closed_read?.should == true
    @io.closed_write?.should == false 
    @io.closed? == false
    @io.close_write
    @io.closed_read?.should == true
    @io.closed_write?.should == true
    @io.closed? == true
  end

  it "should dup" do
    @io.write "1234"
    @io.getc.should == "1"
    io2 = @io.dup
    io2.getc.should == "2"
    @io.getc.should == "3"
    io2.getc.should == "4"
    io2.close_write
    @io.getc.should == nil
    @io.eof?.should == true
    @io.close
    io2.closed?.should == true
  end

  it "should reopen" do
    @io.write("foo\nbar\nbaz\n")
    @io.gets.should == "foo\n"
    @io.reopen("qux\nquux\nquuux\n")
    @io.gets.should == "qux\n"

    io2 = IOString.new
    io2.reopen(@io)
    io2.gets.should == "quux\n"
  end

  it "should read each_byte" do
    @io.write "1234"
    @io.close_write
    a = [] 
    @io.each_byte do |c|
      a << c
    end
    t = %w( 1 2 3 4).map { |c| c.ord }
    a.should == t
  end

  it "should get byte" do
    @io.write "1234"
    @io.close_write
    @io.getbyte.should == "1".ord
    @io.getbyte.should == "2".ord
    @io.getbyte.should == "3".ord
    @io.getbyte.should == "4".ord
    @io.getbyte.should == nil
  end

  it "should not ungetbyte" do
    lambda { @io.ungetbyte(1)}.should raise_error(NameError)
    # shouldn't have removed it from all IOs.
    #
    f = Tempfile.new('foo')
    f.write "foo"
    f.rewind 
    f.getbyte.should == "f".ord
    f.ungetbyte("b")
    f.getbyte.should == "b".ord
    
    #ungetbyte just pushes it back into the buffer, not actually into the file
    f.rewind
    f.read.should == "foo"
    f.close
  end

  it "should ungetc" do
    @io.write "hello"
    lambda { @io.ungetc("x") }.should raise_error(NameError)
   
    f = Tempfile.new('foo')
    f.write "foo"
    f.rewind 
    f.getc.should == "f"
    f.ungetc("b")
    f.getc.should == "b"
    
    #ungetc just pushes it back into the buffer, not actually into the file
    f.rewind
    f.read.should == "foo"
    f.close
  end

  it "should readchar" do
    @io.write "1234"
    @io.close_write
    a = ""
    lambda { loop { a << @io.readchar } }.should raise_error(EOFError)
    a.should == "1234"
  end

  it "should readbyte" do
    @io.write "1234"
    @io.close_write
    a = []
    lambda { loop { a << @io.readbyte} }.should raise_error(EOFError)
    "1234".unpack("C*").should == a
  end

  it "should readbyte with bytewise overflow" do
    @io.write("1" * (IOString::SystemSizeLimit + 1000))
    a = []
    lambda do
      debugger
      IOString::SystemSizeLimit.times do
        a << @io.readbyte
      end
      @io.close_write
      loop do
        a << @io.readbyte
      end
    end.should raise_error(EOFError)
    ("1" * (IOString::SystemSizeLimit + 1000)).unpack("C*").should == a
  end

  it "should get each_char" do
    @io.write "1234"
    @io.close_write 
    %w(1 2 3 4).should == @io.each_char.to_a
  end

  it "should each codepoint" do
    pending "i don't know what this means and am not sure it's necessary"
  end

  it "should address bug 4112" do
    pending = "not fixed until ruby 1.9.3"
    #["a".encode("utf-16be"), "\u3042"].each do |s|
    #  t = IOString.new(s).gets(1)
    #  (s == t).should == true
    #  IOString.new(s).gets(nil,1).should == s
    #end
  end
 
  it "should each it as an enum" do
    @io.write("foo\nbar\nbaz\n")
    @io.close_write
    @io.each.to_a.should == ["foo\n","bar\n","baz\n"]
  end

  it "should each it with a block" do
    @io.write("foo\nbar\nbaz\n")
    ex = ["foo\n","bar\n","baz\n"]
    @io.close_write
    @io.each do |r|
      r.should == ex.shift
    end
  end

  it "should putc" do
    @io.putc "1"
    @io.putc "2"
    @io.putc "3"
    @io.read(3).should == "123"

    io = IOString.new("foo")
    io.putc "1"
    io.putc "2"
    io.putc "3"
    io.read(6).should == "foo123"
  end

  it "should read (encoding aware)" do
    # read is not encoding aware with args - it reads raw bytes
    @io.set_encoding Encoding::UTF_8
    @io.write "\u3042\u3044"
    lambda { @io.read(-1)}.should raise_error(ArgumentError)
    lambda { @io.read(1,2,3,)}.should raise_error(ArgumentError)
    @io.read(2).should == "\xE3\x81"
    @io.read(4) # i just happen to know that.

    @io.write "\u3042\u3044"
    @io.readchars(2).should == "\u3042\u3044"

    @io.write "\u3042\u3044"
    @io.close_write
    @io.read.should == "\u3042\u3044"
  end

  it "should readpartial" do
    # readpartial is not encoding aware
    @io.set_encoding Encoding::UTF_8
    @io.write "\u3042\u3044"
    lambda { @io.readpartial(-1)}.should raise_error(ArgumentError)
    lambda { @io.readpartial(1,2,3,)}.should raise_error(ArgumentError)
    @io.readpartial(IOString::SystemSizeLimit).should == "\u3042\u3044".force_encoding(Encoding::ASCII_8BIT)
  end
   

  it "should read_nonblock" do
    @io.write "\u3042\u3044"
    lambda { @io.read_nonblock(-1)}.should raise_error(ArgumentError)
    lambda { @io.read_nonblock(1,2,3,)}.should raise_error(ArgumentError)
    # a bunch
    @io.read_nonblock(2**16).should == "\u3042\u3044".force_encoding(Encoding::ASCII_8BIT)
  end

  it "is selectable" do
    io2 = IOString.new
    read_array,write_array,error_array = 3.times.collect { [@io,io2].dup }
    
    readable, writable, errors = select(read_array,write_array,error_array,1)

    writable.should == [@io,io2] # both arrays are always readable
    errors.should == [] # no errors yet
    readable.should == [] # nothing readable yet either

    io2.write "hello"
    @io.write "hello"
    
    readable, writable, errors = select(read_array,write_array,error_array,1)
    writable.should == [@io,io2] 
    errors.should == []

    readable.should == [@io,io2]
    readable.each do |r|
      r.read_nonblock(10).should == "hello"
    end

    @io.close_write
    io2.close_write
    
    readable, writable, errors = select(read_array,write_array,error_array,1)
    readable.should == []
    writable.should == []
    error.should == []

    @io.write "hello"
    io2.write "hello"
    
    readable, writable, errors = select(read_array,write_array,error_array,1)
    readable.should == []
    writable.should == []
    errors.should == [@io,io2]
  end
end
