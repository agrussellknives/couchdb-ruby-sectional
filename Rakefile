require 'rest-client'
require 'ruby-debug'
require 'json/pure'
require 'couchrest'
require 'ostruct'

if File.exists? 'config.json' then
  config_obj = JSON.parse(File.open('config.json').read)
else
  config_obj = {}.merge({
  :couch_url => 'http://127.0.0.1:5984',
  :couch_filepath => '/opt/local/var/lib/couchdb',
  :couch_bin => `which couchdb`.chomp
  })
end

COUCH_URL = config_obj['couch_url']
COUCH_FILEPATH = config_obj['couch_filepath']
COUCH_BIN = config_obj['couch_bin']

namespace "couchdb" do
  
  task :gen_config do
    unless File.exists? 'config.json'
      File.open('config.json','w') do |f|
        f.puts JSON.pretty_generate(config_obj)
      end
    else
      puts 'config.json already exists.'
    end
  end
    
  task :restart do
    begin
      RestClient.post 'http://127.0.0.1:5984/_restart',nil, :content_type => 'application/json' do
      end
    rescue RestClient::ServerBrokeConnection => e
      time = Time.now.to_i
      begin
        RestClient.get 'http://127.0.0.1:5984' do |res|
          raise RestClient::Exception unless JSON.parse(res.body)['couchdb'] =~ /welcome/i
          puts "CouchDB restarted!"
          Process.exit
        end
      rescue Errno::ECONNREFUSED
        # keep trying for three second and then give up.
        retry if Time.now.to_i - time < 3
        puts "CouchDB failed to restart."
        Process.exit
      end
    end
  end
  
  task :nuke_views, [:database, :filelist] do |t,args|
    database = args.database || '*'
    filelist = args.filelist || FileList["#{COUCH_FILEPATH}/.#{database}_design/*.view"]
    
    filelist.each do |f|
      puts "deleting file #{f}"
      #File.delete(f) if File.exist?(f)
      puts "View index #{f} deleted."
    end
    Rake::Task["couchdb:restart"].execute
  end
  
  task :reset_views, [:database, :design_doc] do |t,args|
    unless args.database
      puts "You must specifiy a database.  If you really want to delete all view index for all databases, use nuke_views"
      Process.exit
    end
    
    begin
      if not args.design_doc then
        # fetch all design docs
        ddocs = RestClient.get "http://127.0.0.1:5984/#{args.database}/_all_docs?startkey=%22_design%2F%22&endkey=%22_design0%22" do |res| 
          JSON.parse(res.body)['rows'].collect { |i| i['_id'] }
        end
      else
        ddocs = Array.new().push << args.design_doc
      end
      indices = FileList.new()
      ddocs.each do |ddoc|
        ddoc_resource = RestClient::Resource.new "http://127.0.0.1:5984/#{args.database}/_design/#{args.design_doc}"
        begin
          info = nil
          ddoc_resource['_info'].get do |res|
            info = JSON.parse(res.body)
            if(info['updater_running'] || info['compact_running'] || info['waiting_commit']) then
              puts "Can't reset views for #{ddoc} during compaction or view update."
              next
            end
            indices << "#{COUCH_FILEPATH}/.#{args.database}_design/#{info['view_index']['signature']}.view"
          end
        rescue RestClient::Exception => e
          puts e.inspect
          Process.exit
        end
      end
    rescue StandardError => e
      puts e.inspect
      Process.exit
    end
    Rake::Task["couchdb:nuke_views"].execute(Rake::TaskArguments.new([:database, :filelist], [args.database,indices]))
   end
   
end
