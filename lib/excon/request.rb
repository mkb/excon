module Excon
  class Request
    CR_NL     = "\r\n"
    HTTP_1_1  = " HTTP/1.1\r\n"
    FORCE_ENC = CR_NL.respond_to?(:force_encoding)

    def initialize(connection, params)
      @connection = connection
      @params = params
    end
    
    def socket
      @connection.socket
    end

    def process_mock(&block)
      @connection.invoke_stub(@params, &block)
    end
      
    
    def try_request(&block)
      begin


        @params[:headers] = @connection.attributes[:headers].merge(@params[:headers] || {})
        @params[:headers]['Host'] ||= '' << @params[:host] << ':' << @params[:port]
        
        

        # if path is empty or doesn't start with '/', insert one
        unless @params[:path][0, 1] == '/'
          @params[:path].insert(0, '/')
        end
        
        return process_mock(&block) if @params[:mock]
        socket.params = @params

        # start with "METHOD /path"
        request = @params[:method].to_s.upcase << ' '
        if @proxy
          request << @params[:scheme] << '://' << @params[:host] << ':' << @params[:port]
        end
        request << @params[:path]

        # add query to path, if there is one
        case @params[:query]
        when String
          request << '?' << @params[:query]
        when Hash
          request << '?'
          for key, values in @params[:query]
            if values.nil?
              request << key.to_s << '&'
            else
              for value in [*values]
                request << key.to_s << '=' << CGI.escape(value.to_s) << '&'
              end
            end
          end
          request.chop! # remove trailing '&'
        end

        # finish first line with "HTTP/1.1\r\n"
        request << HTTP_1_1

        # calculate content length and set to handle non-ascii
        unless @params[:headers].has_key?('Content-Length')
          @params[:headers]['Content-Length'] = case @params[:body]
          when File
            @params[:body].binmode
            File.size(@params[:body])
          when String
            if FORCE_ENC
              @params[:body].force_encoding('BINARY')
            end
            @params[:body].length
          else
            0
          end
        end

        # add headers to request
        for key, values in @params[:headers]
          for value in [*values]
            request << key.to_s << ': ' << value.to_s << CR_NL
          end
        end

        # add additional "\r\n" to indicate end of headers
        request << CR_NL

        # write out the request, sans body
        socket.write(request)

        # write out the body
        if @params[:body]
          if @params[:body].is_a?(String)
            socket.write(@params[:body])
          else
            while chunk = @params[:body].read(CHUNK_SIZE)
              socket.write(chunk)
            end
          end
        end

        # read the response
        response = Excon::Response.parse(socket, @params, &block)

        if response.headers['Connection'] == 'close'
          @connection.reset
        end

        response
      rescue Excon::Errors::StubNotFound => stub_not_found
        raise(stub_not_found)
      rescue => socket_error
        @connection.reset
        raise(Excon::Errors::SocketError.new(socket_error))
      end

      if @params.has_key?(:expects) && ![*@params[:expects]].include?(response.status)
        @connection.reset
        raise(Excon::Errors.status_error(@params, response))
      else
        response
      end      
    end
    
    def invoke(&block)
      try_request(&block)
    rescue => request_error
      if @params[:idempotent] && [Excon::Errors::SocketError, Excon::Errors::HTTPStatusError].any? {|ex| request_error.kind_of? ex }
        retries_remaining ||= @connection.retry_limit
        retries_remaining -= 1
        if retries_remaining > 0
          if @params[:body].respond_to?(:pos=)
            @params[:body].pos = 0
          end
          retry
        else
          raise(request_error)
        end
      else
        raise(request_error)
      end
    end
  end
end

