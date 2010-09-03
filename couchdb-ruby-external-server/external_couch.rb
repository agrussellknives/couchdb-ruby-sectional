#!/usr/bin/env ruby

require 'json'
require 'ruby-debug'
require 'couch_db'
require 'eval-debugger'

%w(external).each {|mod| require "#{File.dirname(__FILE__)}/external/#{mod}" }

module ExternalCouch  
  include CouchDB
  extend self
  
  ROOT = "http://127.0.0.1:5984"
  
  def log(msg)
    $stderr.puts msg
  end
  
  # this method should never return null!
  def run(command={})
    # parse the query to see what we're doing
    begin
      raise RuntimeError, 400 unless command.is_a?(Hash) and command.has_key? 'path'
      result, code = command['path'][1]
      external = command['path'][1][1..-1]
      begin
        #lazily load the plugin.
        require "#{File.dirname(__FILE__)}/external/#{external}.rb"
        External.handle command
      rescue LoadError => e
        $stderr.puts "#{e.class}: No such external handler for #{external}"
      end
    rescue => e
      #$error.puts e.message if @debug
      if e.message.is_a?(Fixnum) then
        {:code => e.message, :body => e.class}
      end
    end
    {:code => code || 200, :json => result}
  end
  
end

ExternalCouch.loop if __FILE__ == $0