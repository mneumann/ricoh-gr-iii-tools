require 'socket' if RUBY_ENGINE == 'ruby'

module HTTPServer
  module Middleware
  end
end

module HTTPServer::Middleware
    def self.chain(*middlewares, app:)
      root = app
      middlewares.reverse_each do |middleware|
        case middleware
        when Class
          root = middleware.new(root)
        else
          raise "Invalid middleware"
        end
      end
      root
    end
end

class HTTPServer::Middleware::Base
  def initialize(inner)
    @inner = inner
  end
  protected def call_inner(env)
    @inner.call(env)
  end
end

class HTTPServer::Middleware::ReadBody < HTTPServer::Middleware::Base
  def call(env)
    if env['HTTP_CONTENT_LENGTH'] 
      env = env.clone
      env['CONTENT_LENGTH'] = Integer(env['HTTP_CONTENT_LENGTH'][0])
      env['BODY'] = env['rack.input'].read(env['CONTENT_LENGTH'])
    end
    call_inner(env)
  end
end

class HTTPServer::Middleware::MaybeAddContentLength < HTTPServer::Middleware::Base
  def call(env)
    status, headers, body = call_inner(env)
    if body.kind_of?(String) and headers['Content-Length'].nil?
      headers['Content-Length'] = body.size.to_s
    end
    [status, headers, body]
  end
end

class HTTPServer::ConnectionHandler
  attr_reader :socket, :app

  def initialize(socket, app)
    @socket = socket
    @app = app
  end

  def handle_request
    env = {}
    read_request_line(env)
    read_headers(env)
    env['rack.input'] = @socket
    env.freeze
    write_response(env, @app.call(env))
  end

  private def write_response(env, resp)
    status, headers, body = resp

    case status
    when Array
      @socket << "HTTP/1.0 #{status.join(' ')}\r\n"
    when String
      @socket << "HTTP/1.0 #{status}\r\n"
    when 200
      @socket << "HTTP/1.0 200 OK\r\n"
    else
      raise "Invalid status"
    end

    for key, value in headers
      case value
      when Array
        value.each do |entry|
          @socket << "#{key}: #{entry}\r\n"
        end
      when String
        @socket << "#{key}: #{value}\r\n"
      else
        raise "Invalid header value"
      end
    end

    @socket << "\r\n" 

    if body.respond_to?(:each)
      body.each do |part|
        @socket << part
      end
    else
      case body
      when nil
      when String
        @socket << body
      else
        raise "Invalid body"
      end
    end

    @socket.close if connection_close?(env, headers)
  end

  private def connection_close?(env, response_headers)
    return true if env['SERVER_PROTOCOL'].casecmp?("HTTP/1.0")
    return true if response_headers.any? {|h, v|
      h.casecmp?('Connection') and
        (v.kind_of?(String) ? v =~ /Close/i : v.any?{|vv| vv =~ /Close/i})
    }
    false
  end

  private def read_request_line(env)
    env['REQUEST_METHOD'],
      env['REQUEST_PATH'],
      env['SERVER_PROTOCOL'] = @socket.readline.strip.split(' ', 3)
    env['PATH_INFO'], env['QUERY_STRING'] = env['REQUEST_PATH'].split('?', 2)
  end

  private def read_headers(env)
    loop do
      line = @socket.readline.chomp
      break if line.empty?
      name, value = line.split(":", 2).map(&:strip)
      http_name = 'HTTP_' + convert_header_name(name)
      (env[http_name] ||= []) << value
    end
  end

  private def convert_header_name(name)
    name.upcase.tr('-', '_').gsub(' ', '')
  end
end

class HTTPServer::Server
  def initialize(host:, port:, app: )
    @host, @port, @app = host, port, app
  end
  def start
    server = TCPServer.new(@host, @port)
    loop do
      conn = HTTPServer::ConnectionHandler.new(server.accept, @app)
      Thread.new do 
        begin
          conn.handle_request
        rescue
          conn.socket.close
        end
      end
    end
  end
end

if __FILE__ == $0
  class App
    def call(env)
      p env['BODY']
      return [
        '200 OK',
        {'Content-Type' => 'text/plain',
         'Date' => 'Sat, 09 Oct 2010 14:28:02 GMT',
         'Connection' => 'Close'
        },
        "12345678" 
      ]
    end
  end

  app = HTTPServer::Middleware.chain(
      HTTPServer::Middleware::MaybeAddContentLength,
      HTTPServer::Middleware::ReadBody,
      app: App.new)

  server = HTTPServer::Server.new(host: '127.0.0.1', port: 8080, app: app)
  server.start
end
