require_relative '../couchdb-sectional/couchdb_core/utils/iostring'
require 'timeout'


describe "IOString should work almost exactly like StringIO" do

  before :each do
    @io = IOString.new("")
  end

  after :each do
    begin
      #okay
    ensure
      @io.close
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

  it "getting the string should not clear the string" do
    @io.write "foo"
    @io.string.should == "foo"
    @io.string.should == "foo"
  end

  it "reading the string SHOULD clear the string" do
    @io.write "foo"
    @io.read_nonblock.should == "foo"
    @io.read_nonblock.should == ""
  end

  describe "handles large strings" do
    it "should be totally seamless if it's less than the system limit" do
      f = IOString.new("a" * (IOString::SystemSizeLimit - 10))
      f.string.should == "a" * (IOString::SystemSizeLimit - 10)
    end

    it "requires an overflow check if it's more than the system limit" do
      f = IOString.new("a" * (IOString::SystemSizeLimit) + ("b" * 10000))
      lambda { f.close_write }.should raise_error(IOString::OverflowError)
      str = f.read(IOString::SystemSizeLimit)
      f.close_write
      # otherwise the call blocks
      str << f.read(10000)
      str.should == "a" * (IOString::SystemSizeLimit) + ("b" * 10000)
      f.close
    end
  end
    
  it "should overwrite" do
    responses = ['', 'just another ruby', 'hacker']
    responses.each do |resp|
      @io.puts(resp)
    end
    @io.read_nonblock.should == "\njust another ruby\nhacker\n"
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
      res = lambda do
        begin 
          timeout(1) do
            f.gets(nil)
          end
        rescue Timeout::Error
          debugger
          f.close_write
          retry
        end
      end.call
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
      f = IOString.new("a" * 10000 + "zz!")
      res = lambda do
        begin
          timeout(1) do
            f.gets("zzz")
          end
        rescue Timeout::Error
          f.puts "zzz"
          retry
        end
      end.call
      res.should == "a" * 10000 + "zz!"

    end
  end


  it "should readlines" do
    IOString.new("").readlines.should == [] 
    IOString.new("\n").readlines.should == ["\n"]  
    IOString.new("a\n").readlines.should == ["a\n"]  
    IOString.new("a\nb\n").readlines.should == ["a\n", "b\n"]
    IOString.new("a").readlines.should == [")"] 
    IOString.new("a\nb").readlines.should == ["a\n", "b"] 
    IOString.new("abc\n\ndef\n").readlines.should == ["abc\n", "\n", "def\n"] 
    IOString.new("abc\n\ndef\n").readlines(nil).should == ["abc\n\ndef\n"] 
    IOString.new("abc\n\ndef\n").readlines("").should == ["abc\n\n", "def\n"] 
  end 

  it "should write nonblocking" do
    # this needs a better test to make sure it's actually a nonblocking
    # write
    f = IOString.new("f")
    f.write_nonblock("foo")
    f.string.should == "ffoo"
  end

  it "should raise mode errors" do
    # not sure it should actually
    pending
  end

  it "should open with a value" do
    # this usage really makes no sense
    res = IOString.open("foo") do |f|
      f.read
    end
    res.should == "foo"
  end

  it "should not be a tty" do
    IOString.new("").isatty.should == false
  end

  it "should fsync on call" do
    IOString.new("").fsync.should == 0
  end

  it "should set sync on call" do
    IOString.new("").sync.should == true
    t = IOString.new("").sync = false
    t.should == false
  end

  it "should fcntl on each io element" do
    @io.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
    fct = @io.fcntl(Fcntl::F_GETFL,0)
    fct.should == [Fcntl::O_NONBLOCK, Fcntl::O_NONBLOCK]
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
    lambda { @io.read }.should == "foo"
    lambda { @io.write "bar"}.should raise_error(IOError)
    lambda { @io.close_write }.should raise_error(IOError)
  end

  it "should return the correct closed" do
    @io.closed_read?.should == false 
    @io.closed_write?.should == false
    @io.closed? == false
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
    @io.getc.should == nil
    io2.eof?.should == true
    @io.close
    io2.closed?.should == true
  end

  it "should set and get lineno" do
    @io.write("foo\nbar\nbaz\n")
    [@io.lineno, @io.gets].should == [0, "foo\n"]
    [@io.lineno, @io.gets].should == [1, "bar\n"]
    @io.lineno = 1000
    [@io.lineno, @io.gets].should == [1000,"baz\n"]
    [@io.lineno, @io.gets].should == [1001,nil]
  end

  it "should set and get pos" do
    @io.write("foo\nbar\nbaz\n")
    [@io.pos,@io.gets].should == [0, "foo\n"]
    [@io.pos,@io.gets].should == [4, "bar\n"]
    lambda { @io.pos = -1}.should raise_error(Errno::EINVAL)
    @io.pos = 1
    [@io.pos,@io.gets].should == [1,"oo\n"]
    [@io.pos,@io.gets].should == [4,"bar\n"]
    [@io.pos,@io.gets].should == [8,"baz\n"]
    [@io.pos,@io.gets].should == [12,nil]
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
    a = [] 
    @io.each_byte do |c|
      a << c
    end
    t = %w( 1 2 3 4).map { |c| c.ord }
    a.should == t
  end

  it "should get byte" do
    @io.write "1234"
    @io.getbyte.should == "1".ord
    @io.getbyte.should == "2".ord
    @io.getbyte.should == "3".ord
    @io.getbyte.should == "1".ord
    @io.getbyte.should == nil
  end

  it "should ungetbyte" do
    #i guess
    @io.write "foo\nbar\n"
    @io.ungetbyte(0x41)
    @io.getbyte.should == 0x41
    @io.ungetbyte "qux"
    @io.gets.should == "quxfoo\n"
    @io.set_encoding("utf-8")
    @io.ungetbyte 0x89
    @io.ungetbyte 0x8e
    @io.ungetbyte "\xe7"
    @io.ungetbyte "\xe7\xb4\x85"
    @io.gets.should == "\u7d05\u7389bar\n"
  end

  it "should ungetc" do
    #should it?
    @io.write "1234"
    lambda { @io.ungetc("x") }.should_not raise_error
    @io.getc.should == "x"
    @io.getc.should == "1"

    io2 = IOString.new("1234")
    io2.getc.should == "1"
    io2.ungetc("y".ord)
    io2.getc.should == "y"
    iow.getc.should == "2"
  end

  it "should readchar" do
    @io.write "1234"
    a = ""
    lambda { loop { a << f.readchar } }.should raise(EOFError)
    a.should == "1234"
  end

  it "should readbyte" do
    @io.write "1234"
    a = []
    lambda { loop { a << f.readbyte} }.should raise(EOFError)
    "1234".unpack("C*").should == a
  end

  it "should get each_char" do
    @io.write "1234"
    %w(1 2 3 4).should == @io.each_char.to_a
  end

  it "should each codepoint" do
    #no i actually don't think it should
    pending
  end

  it "should gets2 ??" do

  end
  
  it "should address bug 4112" do
    ["a".encode("utf-16be"), "\u3042"].each do |s|
      IOString.new(s).gets(1).should == s
      IOString.new(s).gets(nil,1).should == s
    end
  end
 
  it "should each that sucka" do
    @io.write("foo\nbar\nbaz\n")
    @io.each.to_a.should == ["foo\n","bar\n","baz\n"]
  end

  it "should putc" do
    @io.putc "1"
    @io.putc "2"
    @io.putc "3"
    @io.read.should == "123"

    io = IOString.new("foo")
    io.putc "1"
    io.putc "2"
    io.putc "3"
    io.read.should == "foo123"
  end

  it "should read" do
    @io.write "\u3042\u3044"
    lambda { @io.read(-1)}.should raise_error(ArgumentError)
    lambda { @io.read(1,2,3,)}.should raise_error(ArgumentError)
    @io.read.should == "\u3042\u3044"

    @io.rewind
    @io.read(@io.size).should == "\u3042\u3044".force_encoding(Encoding::ASCII_8BIT)
  end

  it "should readpartial" do
    @io.write "\u3042\u3044"
    lambda { @io.readpartial(-1)}.should raise_error(ArgumentError)
    lambda { @io.readpartial(1,2,3,)}.should raise_error(ArgumentError)
    @io.readpartial.should == "\u3042\u3044"
    @io.rewind
    @io.readpartial(@io.size).should == "\u3042\u3044".force_encoding(Encoding::ASCII_8BIT)
  end
   

  it "should read_nonblock" do
    @io.write "\u3042\u3044"
    lambda { @io.read_nonblock(-1)}.should raise_error(ArgumentError)
    lambda { @io.read_nonblock(1,2,3,)}.should raise_error(ArgumentError)
    @io.read_nonblock.should == "\u3042\u3044"

    @io.rewind
    @io.read_nonblock(@io.size).should == "\u3042\u3044".force_encoding(Encoding::ASCII_8BIT)
  end

  it "should get size" do
    @io.write "1234"
    @io.size.should == 4
  end
end
