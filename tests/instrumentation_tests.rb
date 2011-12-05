require 'active_support/notifications'

Shindo.tests('Instrumentation of connections') do
  # Excon.mock = true

  before do
    @events = []
  end

  after do
    # flush any existing stubs after each test
    Excon.stubs.clear
  end

  with_rackup('request_methods.ru') do
    tests('basic notification').returns('excon.request') do
      ActiveSupport::Notifications.subscribe(/excon/) do |*args|
        @events << ActiveSupport::Notifications::Event.new(*args)
      end

      Excon.get('http://localhost:9292').body

      @events.first.name
    end
  end

    tests('notify on retry')
    tests('notify on error')
    tests('filtering')
    tests('indicates duration')
    # excon.request
    # excon.error
    # excon.retry
end