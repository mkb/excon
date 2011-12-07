require 'active_support/notifications'

Shindo.tests('Instrumentation of connections') do
  before do
    Excon.mock = true
  end

  after do
    ActiveSupport::Notifications.unsubscribe("excon")    #
    Excon.stubs.clear
    Excon.mock = false
  end

  def subscribe(match)
    @events = []
    ActiveSupport::Notifications.subscribe(match) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def make_request(idempotent = false)
    connection = Excon.new('http://127.0.0.1:9292',
        :instrumentor => ActiveSupport::Notifications)
    if idempotent
      connection.get(:idempotent => true)
    else
      connection.get()
    end
  end

  tests('basic notification').returns('excon.request') do
    subscribe(/excon/)
    Excon.stub({:method => :get}) { |params|
      {:body => params[:body], :headers => params[:headers], :status => 200}
    }

    make_request
    @events.first.name
  end

  tests('notify on retry').returns(3) do
    subscribe(/excon/)
    run_count = 0
    Excon.stub({:method => :get}) { |params|
      run_count += 1
      if run_count <= 3 # First 3 calls fail.
        raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
      else
        {:body => params[:body], :headers => params[:headers], :status => 200}
      end
    }

    make_request(true)
    @events.select{|e| e.name =~ /retry/}.count
  end

  tests('notify on error').returns(1) do
    subscribe(/excon/)
    Excon.stub({:method => :get}) { |params|
      raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
    }

    raises(Excon::Errors::SocketError) do
      make_request
    end

    @events.select{|e| e.name =~ /error/}.count
  end

  tests('filtering').returns(2) do
    subscribe(/excon.request/)
    subscribe(/excon.error/)
    Excon.stub({:method => :get}) { |params|
      raise Excon::Errors::SocketError.new(Exception.new "Mock Error")
    }

    raises(Excon::Errors::SocketError) do
      make_request(true)
    end

    returns(true) {@events.any? {|e| e.name.match(/request/)}}
    returns(false) {@events.any? {|e| e.name.match(/retry/)}}
    returns(true) {@events.any? {|e| e.name.match(/error/)}}
    @events.select{|e| e.name =~ /excon/}.count
  end

  tests('indicates duration').returns(true) do
    subscribe(/excon/)
    delay = 30
    Excon.stub({:method => :get}) { |params|
      Delorean.jump delay
      {:body => params[:body], :headers => params[:headers], :status => 200}
    }

    make_request
    (@events.first.duration/1000 - delay).abs < 1
  end

  tests('filtering the opposite way')
  tests('allows random instrumentor instead of ActiveSupport')
  tests('works unmocked')
end