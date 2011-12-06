require 'active_support/notifications'

Shindo.tests('Instrumentation of connections') do
  # Excon.mock = true

  after do
    ActiveSupport::Notifications.unsubscribe("excon")    #
    Excon.stubs.clear
  end

  with_rackup('request_methods.ru') do
    @events = []
    tests('basic notification').returns('excon.request') do
      ActiveSupport::Notifications.subscribe(/excon/) do |*args|
        @events << ActiveSupport::Notifications::Event.new(*args)
      end

      Excon.get('http://localhost:9292')

      @events.first.name
    end
  end

  Excon.mock = true
  tests('notify on retry').returns(3) do
    @events = []
    ActiveSupport::Notifications.subscribe(/excon/) do |*args|
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

    @events.select{|e| e.name =~ /retry/}.count
  end

  Excon.mock = true
  tests('notify on error').returns(1) do
    @events = []
    ActiveSupport::Notifications.subscribe(/excon/) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end

    Excon.stub({:method => :get}) { |params|
      raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
    }

    connection = Excon.new('http://127.0.0.1:9292')
    raises(Excon::Errors::SocketError) do
      response = connection.request(:method => :get, :path => '/some-path')
    end

    @events.select{|e| e.name =~ /error/}.count
  end
  Excon.mock = false

  Excon.mock = true
  tests('filtering').returns(2) do
    @events = []
    ActiveSupport::Notifications.subscribe(/excon.request/) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end

    ActiveSupport::Notifications.subscribe(/excon.error/) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end

    Excon.stub({:method => :get}) { |params|
      raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
    }

    connection = Excon.new('http://127.0.0.1:9292')
    raises(Excon::Errors::SocketError) do
      response = connection.request(:method => :get, :path => '/some-path')
    end

    returns(true) {@events.any? {|e| e.name.match(/request/)}}
    returns(false) {@events.any? {|e| e.name.match(/retry/)}}
    returns(true) {@events.any? {|e| e.name.match(/error/)}}
    @events.select{|e| e.name =~ /excon/}.count
  end
  Excon.mock = false

  Excon.mock = true
  tests('indicates duration').returns(true) do
    @events = []
    ActiveSupport::Notifications.subscribe(/excon/) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end

    delay = 30
    Excon.stub({:method => :get}) { |params|
      Delorean.jump delay
      {:body => params[:body], :headers => params[:headers], :status => 200}
    }

    connection = Excon.new('http://127.0.0.1:9292')
    response = connection.request(:method => :get, :path => '/some-path')

    @events.select{|e| e.name =~ /retry/}.count
    (@events.first.duration/1000 - delay).abs < 1
  end
  Excon.mock = false

  tests('does not require activesupport')
end