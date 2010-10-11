require 'optparse'

module Arguments
  
  attr_accessor :options
  
  DEPENDENT = {
    :debug => {:unsafe => true},
    :wait => {:debug => true, :unsafe => true},
    :stop => {:debug => true, :unsafe => true},
    :stderr_to => {:debug => true, :unsafe => true}
  }

  DEFAULT = {
    :debug => false,
    :stop => false,
    :wait => false,
    :stderr_to => nil,
    :unsafe => false,
    :pipe => false
  } 

  def default_merge
    check_opt = @options.clone
  
    check_opt.each do |opt,val|
      next if not DEPENDENT.key?(opt)
      arr = DEPENDENT[opt].select do |depopt,ev|
        true if options[depopt] == ev
      end
      @options[opt] = (arr.size == DEPENDENT[opt].size ? @options[opt] : DEFAULT[opt])
    end
  end
  module_function :default_merge
  
  def apply
    @options.each_pair do |opt,val|
      next unless val #the default value of everything is false, so if the val is false, we can skip it.
      case opt
        when :debug 
          CouchDB.debug = true
          require 'ruby-debug'
          require 'eval-debugger'
        when :stop 
          CouchDB.stop_on_error = true
        when :wait 
          CouchDB.wait_for_connection = true
        when :stderr_to 
          CouchDB.stderr_to = val
        when :unsafe
          CouchDB::Sandbox.safe = false
      end
    end
  end
  module_function :apply

  def parse_args args
    @options = DEFAULT.clone
    begin
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: add the path this couchdb_view_server in your couchdb.ini file, and specify options there."
        opts.separator ""
        opts.separator "Using any of the debug settings will slow the view server down considerably."
        opts.separator "Specific Options:"

        opts.on('-f','--file FILENAME','Output STDERR to file FILENAME. Ignored if --debug and --unsafe are not given') do |file|
          @options[:stderr_to] = file
        end
        opts.on('--debug','-u','Enable debugging of Query Server Functions.  Ignored if --unsafe is not given.') do
          @options[:debug] = true
        end
        opts.on('--stop-on-error','-s','Wait for a debugger to connect if an exception is thrown.  Ignored if --debug is not given') do
          @options[:stop] = true
        end
        opts.on('--wait','-w','Wait for debugger connection on startup. Ignored if --debug is not given.') do
          @options[:wait] = true
        end
        opts.on('--unsafe',"Don't sandbox Query Server Functions. DANGEROUS.") do
          @options[:unsafe] = true
        end
        opts.on('-r FILE','require a file into the view server so it can be accessed within view functions') do |file|
          require file.lstrip.rstrip
        end
        opts.on('-h','--help','Display this screen') do
          puts opts
          exit
        end
      end
      opts.parse! args
      default_merge
      apply
    rescue => e
      puts e, e.backtrace
      Process.exit
    end
  end 
  module_function :parse_args
  public :parse_args

end

