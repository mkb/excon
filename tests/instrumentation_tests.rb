require 'active_support/notifications'

Shindo.tests('Instrumentation of connections') do
  with_rackup('request_methods.ru') do
    tests('nada').returns([:cheezburger]) do
      
      @notifications = []
      
      ActiveSupport::Notifications.subscribe(/cheezburger/) do |event|
        @notifications << event
      end
      
      ActiveSupport::Notifications.instrument(:cheezburger) do
        Excon.get('http://localhost:9292').body
      end
      
      @notifications
    end
  end
end