if RUBY_ENGINE == 'ruby'
  $LOAD_PATH.unshift 'mrblib' 
  require 'http_server'
end

class App
  def call(conn)
    if conn.method == 'get' && conn.request_path == '/'
      index(conn)
      return
    end
    if conn.method == 'get' && conn.request_path == '/liveview'
      liveview(conn)
      return
    end

    not_found(conn)
  end

  def liveview(conn)
    camera = TCPSocket.new('192.168.0.1', 80)
    camera << "GET /v1/liveview HTTP/1.0\r\n" 
    camera << "Host: 192.168.0.1\r\n" 
    camera << "\r\n"
    camera.flush
    conn.adapter.socket << camera.readline
    loop do
      header = camera.readline.chomp
      if header.empty?
        conn.adapter.socket << "\r\n"
        break
      end
      key, value = header.split(':', 2)
      case key.downcase
      when 'host' 
        value = conn.host
      end

      conn.adapter.socket << "#{key}: #{value}\r\n"
    end

    while buf = camera.read(4096)
      conn.adapter.socket << buf
    end
    conn.adapter.socket.close
  end

  def index(conn)
    body = <<-BODY
    <!DOCTYPE html>
    <html>
        <head>
            <title>Live View</title>
        </head>
        <body style="margin: 0; padding: 0;">
            <img src="/liveview" style="width: 50vw; height: 50vh;">
        </body>
    </html>
    BODY

    conn
      .put_resp_content_type('text/html')
      .put_resp_header('date', 'Sat, 09 Oct 2010 14:28:02 GMT')
      .put_resp_header('content-length', body.size)
      .resp(200, body)
      .send_resp
  end

  def not_found(conn)
    conn
      .put_resp_content_type('text/plain')
      .put_resp_header('date', 'Sat, 09 Oct 2010 14:28:02 GMT')
      .resp(404, 'Not found')
      .send_resp
  end
end

if __FILE__ == $0
  server = HTTPServer.new(host: '127.0.0.1', port: 8080, handler: App.new)
  server.start
end


