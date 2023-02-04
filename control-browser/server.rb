if RUBY_ENGINE == 'ruby'
  $LOAD_PATH.unshift 'mrblib' 
  require 'http_server'
end

class App
  def initialize(ricoh_ip: "192.168.0.1")
    @ricoh_ip = ricoh_ip
  end

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
            <style type="text/css">
            body {
              margin:0; 
              padding:0;
              background: #020202;
              width: 100vw;
              height: 100vh;
            }
            .container {
              width: 100%;
              height: 100%;
              display: flex;
              justify-content: center;
              flex-direction: row;
            }
            #liveview {
              aspect-ratio: 3/2;
              height: 100%;
              margin:0;
              padding:0;
              cursor: crosshair;
            }
            .control {
              width: 4em;
              height: 3em;
              background: #9f9f9f;
              margin: 2em;
              padding: 1em;
            }
            </style>
        </head>
        <body onload="setup()">
          <script>
            function shoot({af, posX, posY})
            {
              console.log({af, posX, posY});
              var body = "af=" + (af ? "on" : "off") + "&pos=" + posX.toString() + "," + posY.toString();

              const headers = {'Content-Type': 'application/x-www-form-urlencoded'};
              fetch('/shoot', { headers, method: 'POST', body: body })
              .then((response) => response.json())
              .then((data) => console.log(data));
            }

            function handleClick(ev)
            {
              shoot({
                af: document.getElementById("af").checked,
                posX: calcPosX(ev),
                posY: calcPosY(ev)
              });
              return false;
            }

            function handleMove(ev) {
              const posX = calcPosX(ev);
              const posY = calcPosY(ev);
              const text = posX.toString() + " " + posY.toString();
              const posEl = document.getElementById("pos").innerHTML = text;
              return false;
            }

            function calcPosX(ev) { return Math.trunc(100.0 * ev.offsetX / ev.target.clientWidth); }
            function calcPosY(ev) { return Math.trunc(100.0 * ev.offsetY / ev.target.clientHeight); }

            function setup() {
              document.getElementById('liveview').addEventListener('mousemove', handleMove); 
            }
          </script>
          <div class="container">
            <img id="liveview" src="/liveview" onclick="handleClick(event)" onmove="handleMove(event)">
            <div class="control">
              <label for="af">AF <input id="af" type="checkbox" checked></label>
              <div id="pos">? ?</div>
            <div>
          </div>
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

    camera = TCPSocket.new(@ricoh_ip, 80)
    camera << "POST /v1/camera/shoot HTTP/1.0\r\n" 
    camera << "Host: #{@ricoh_ip}\r\n" 
    camera << "Content-Type: application/x-www-form-urlencoded\r\n" 
    camera << "Content-Length: #{body.length}\r\n"
    camera << "\r\n"
    camera << body
    camera.flush
    _proxy(from_socket: camera, to_conn: conn, debug: true)
  end

  def liveview(conn)
    camera = TCPSocket.new(@ricoh_ip, 80)
    camera << "GET /v1/liveview HTTP/1.0\r\n" 
    camera << "Host: #{@ricoh_ip}\r\n" 
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


