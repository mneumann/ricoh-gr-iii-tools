require 'socket' if RUBY_ENGINE == 'ruby'

module Plug
end

class Plug::Header < Struct.new(:key, :value); end

class Plug::Conn
  attr_reader :adapter, :host, :method, :request_path, :req_headers, :query_string

  attr_reader :resp_headers, :state, :status, :resp_body

  def initialize(adapter:, host:, method:, request_path:, req_headers:, query_string:)
    @adapter, @host, @method, @request_path, @req_headers, @query_string =
      adapter, host, method, request_path, req_headers, query_string

    @resp_headers = []
    @state = nil
    @status = nil
    @resp_body = nil
  end

  def get_req_header(key)
    @req_headers.filter_map {|h| h.key == key ? h.value : nil}
  end

  def sent?
    @state == :sent
  end

  def put_resp_header(key, value)
    raise if sent?
    @resp_headers.each do |h|
      if h.key == key
        h.value = value
        return
      end
    end
    @resp_headers << Plug::Header.new(key, value)
    self
  end

  def put_resp_content_type(content_type)
    put_resp_header('content-type', content_type)
  end

  def resp(status, body)
    raise if sent? or @state == :set
    @state = :set
    @status = status
    @resp_body = body
    self
  end

  def send_resp
    raise if sent?
    raise if @state != :set

    @adapter.send_resp(@status, @resp_headers, @resp_body)
    @state = :sent

    self
  end
end

class HTTPServer
  def initialize(host:, port:, handler:)
    @host, @port, @handler = host, port, handler
  end

  def start
    server = TCPServer.new(@host, @port)
    loop do
      socket = server.accept
      Thread.new { handle_request(socket) }
    end
  end

  private def handle_request(socket)
    adapter = HTTPServer::Adapter.new(socket)
    @handler.call(make_conn(adapter))
  rescue => ex
    STDERR.puts "ERROR: #{ex}"
    adapter.close
  end

  private def make_conn(adapter)
    # read request line
    method, path, proto = adapter._read_request_line
    request_path, query_string = path.split('?', 2) 

    # read headers
    req_headers = []
    loop do
      line = adapter.socket.readline.chomp
      break if line.empty?
      key, value = line.split(":", 2).map(&:strip)
      req_headers << Plug::Header.new(map_header_key(key), value)
    end

    Plug::Conn.new(
      adapter: adapter,
      host: @host,
      method: method.downcase,
      request_path: request_path,
      req_headers: req_headers,
      query_string: query_string)
  end

  private def map_header_key(key)
    key.downcase
  end
end

class HTTPServer::Adapter < Struct.new(:socket)
  def close
    socket.close
  end

  def _read_request_line
    method, path, proto = socket.readline.strip.split(' ', 3)
    @proto = proto.downcase
    [method, path, proto]
  end

  def send_resp(status, resp_headers, resp_body)
    sock = self.socket

    sock << "HTTP/1.0 #{status} #{status_text(status)}\r\n"
    resp_headers.each {|h| sock << "#{h.key}: #{h.value}\r\n"}
    sock << "\r\n" 
    sock << resp_body

    # We answer in HTTP/1.0, which always closes connection unless keep-alive
    # is specified.
    if resp_headers.any? {|h| h.key == 'connection' && h.value == 'keep-alive'}
      # keep open... TODO
    elsif resp_headers.any? {|h| h.key == 'connection' && h.value == 'close'}
      sock.close
    else
      sock.close
    end
  end

  private def status_text(status)
    case status
    when 200 then "OK"
    when 404 then "Not Found"
    else
      raise "Unknown status"
    end
  end
end

if __FILE__ == $0
  class App
    def call(conn)
      if content_length = conn.get_req_header('content-length').first.then(&:to_i)
        p conn.adapter.socket.read(content_length)
      end

      conn
        .put_resp_content_type('text/plain')
        .put_resp_header('date', 'Sat, 09 Oct 2010 14:28:02 GMT')
        .resp(200, '12345')
        .send_resp
    end
  end

  server = HTTPServer.new(host: '127.0.0.1', port: 8080, handler: App.new)
  server.start
end
