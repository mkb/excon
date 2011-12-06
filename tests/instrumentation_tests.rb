require 'active_support/notifications'
require 'ruby_debug'

Shindo.tests('Instrumentation of connections') do
  # Excon.mock = true


  before do
    @events = []
  end

  after do
    ActiveSupport::Notifications.unsubscribe("excon")    #
    Excon.stubs.clear
  end

  with_rackup('request_methods.ru') do
    tests('basic notification').returns('excon.request') do
      ActiveSupport::Notifications.subscribe(/excon/) do |*args|
        @events << ActiveSupport::Notifications::Event.new(*args)
      end
  
      Excon.get('http://localhost:9292')
  
      @events.first.name
    end
  end

  Excon.mock = true
  tests('notify on retry').returns(4) do
    ActiveSupport::Notifications.subscribe(/excon/) do |*args|
      puts "BLOP"
      @events << ActiveSupport::Notifications::Event.new(*args)
    end

    run_count = 0
    Excon.stub({:method => :get}) { |params|
      run_count += 1
      if run_count <= 3 # First 3 calls fail.
        raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
      else
        {:body => params[:body], :headers => params[:headers], :status => 200}
      end
    }

    connection = Excon.new('http://127.0.0.1:9292')
    response = connection.request(:method => :get, :idempotent => true, :path => '/some-path')

    p @events.collect(&:name)
    @events.select{|e| e.name =~ /retry/}.count
  end
  Excon.mock = false

  tests('notify on error')
  tests('filtering')
  tests('indicates duration')
  # excon.request
  # excon.error
  # excon.retry
end