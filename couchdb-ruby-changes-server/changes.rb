require "json"
require "ruby-debug"

%w(changes_listener changes_listener_group).each {|mod| require "#{File.dirname(__FILE__)}/changes/#{mod}" }

module ExternalCouch
  module External
    def changes
    end
  end
end
  