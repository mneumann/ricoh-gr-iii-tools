if RUBY_ENGINE == 'ruby'
  $LOAD_PATH.unshift 'mrblib' 
  require 'http_server'
end

class App
  def call(conn)
    return index(conn) if conn.method == 'get' && conn.request_path == '/'
    return liveview(conn) if conn.method == 'get' && conn.request_path == '/liveview'
    return shoot(conn) if conn.method == 'post' && conn.request_path == '/shoot'
    not_found(conn)
  end

  def index(conn)
    body = <<-BODY
    <!DOCTYPE html>
    <html>
        <head>
            <title>Live View</title>
        </head>
        <body style="margin: 0; padding: 0;">
          <script>
            function shoot({af, posX, posY})
            {
              var body = "af=" + (af ? "on" : "off") + "&pos=" + posX.toString() + "," + posY.toString();

              const headers = {'Content-Type': 'application/x-www-form-urlencoded'};
              fetch('/shoot', { headers, method: 'POST', body: body })
              .then((response) => response.json())
              .then((data) => console.log(data));
            }
            function handleClick(ev)
            {
              const posX = Math.trunc(100.0 * ev.clientX / ev.target.clientWidth);
              const posY = Math.trunc(100.0 * ev.clientY / ev.target.clientHeight);
              console.log({posX, posY});
              shoot({af: true, posX, posY});
              return false;
            }
          </script>
          <img src="/liveview" style="width: 135vh; height: 90vh;" onclick="handleClick(event)">
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

  def shoot(conn)
    if content_length = conn.get_req_header('content-length').first.then(&:to_i)
      body = conn.adapter.socket.read(content_length)
    else
      raise 'no content-length'
    end

    camera = TCPSocket.new('192.168.0.1', 80)
    camera << "POST /v1/camera/shoot HTTP/1.0\r\n" 
    camera << "Host: 192.168.0.1\r\n" 
    camera << "Content-Type: application/x-www-form-urlencoded\r\n" 
    camera << "Content-Length: #{body.length}\r\n"
    camera << "\r\n"
    camera << body
    camera.flush
    _proxy(from_socket: camera, to_conn: conn, debug: true)
  end

  def liveview(conn)
    camera = TCPSocket.new('192.168.0.1', 80)
    camera << "GET /v1/liveview HTTP/1.0\r\n" 
    camera << "Host: 192.168.0.1\r\n" 
    camera << "\r\n"
    camera.flush
    _proxy(from_socket: camera, to_conn: conn)
  end

  def not_found(conn)
    conn
      .put_resp_content_type('text/plain')
      .put_resp_header('date', 'Sat, 09 Oct 2010 14:28:02 GMT')
      .resp(404, 'Not found')
      .send_resp
  end

  private def _proxy(from_socket:, to_conn:, debug: false)
    to_conn.adapter.socket << from_socket.readline
    loop do
      header = from_socket.readline.chomp
      if header.empty?
        to_conn.adapter.socket << "\r\n"
        break
      end
      key, value = header.split(':', 2)
      case key.downcase
      when 'host'
        value = conn.host
      end

      to_conn.adapter.socket << "#{key}: #{value}\r\n"
    end

    while buf = from_socket.read(4 * 4096)
      to_conn.adapter.socket << buf
    end
    to_conn.adapter.socket.close
  end
end

if __FILE__ == $0
  server = HTTPServer.new(host: '127.0.0.1', port: 8080, handler: App.new)
  server.start
end


