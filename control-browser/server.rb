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
    return browser(conn) if conn.method == 'get' && conn.request_path == '/browser'
    return props(conn) if conn.method == 'get' && conn.request_path == '/props'
    return liveview(conn) if conn.method == 'get' && conn.request_path == '/liveview'
    return shoot(conn) if conn.method == 'post' && conn.request_path == '/shoot'
    return photos(conn) if conn.method == 'get' && conn.request_path.start_with?('/v1/photos')
    return styles(conn) if conn.method == 'get' && conn.request_path == '/styles.css'
    not_found(conn)
  end

  STYLES = <<-ENDSTYLES
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

    #thumbnails {
      display: flex;
      flex-wrap: wrap;
    }

    .img {
      margin: 10px;
      width: 480px; 
      height: 360px;
    }
  ENDSTYLES

  def styles(conn)
    body = STYLES
    conn
      .put_resp_content_type('text/css')
      .put_resp_header('date', 'Sat, 09 Oct 2010 14:28:02 GMT')
      .put_resp_header('content-length', body.size)
      .resp(200, body)
      .send_resp
  end

  def index(conn)
    body = <<-BODY
    <!DOCTYPE html>
    <html>
        <head>
            <title>Live View</title>
            <link rel="stylesheet" type="text/css" href="/styles.css">
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
              document.getElementById("pos").innerHTML = text;
              return false;
            }

            function calcPosX(ev) { return Math.trunc(100.0 * ev.offsetX / ev.target.clientWidth); }
            function calcPosY(ev) { return Math.trunc(100.0 * ev.offsetY / ev.target.clientHeight); }

            function setup() {
              document.getElementById('liveview').addEventListener('mousemove', handleMove); 
            }

            function showProps() {
              fetch('/props')
              .then((response) => response.json())
              .then((data) => console.log(data));
              return false;
            }
          </script>
          <div class="container">
            <img id="liveview" src="/liveview" onclick="handleClick(event)" onmove="handleMove(event)">
            <div class="control">
              <label for="af">AF <input id="af" type="checkbox" checked></label>
              <div id="pos">? ?</div>
              <button onclick="showProps()">Props</button>
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

  def browser(conn)
    body = <<-BODY
    <!DOCTYPE html>
    <html>
        <head>
            <title>Image Browser</title>
            <link rel="stylesheet" type="text/css" href="/styles.css">
        </head>
        <body onload="setup()">
          <script>
            function setup() {
              fetch('/v1/photos')
              .then((response) => response.json())
              .then((data) => {
                console.log(data);
                const width = 320;
                const height = 240;
                const size = 'view';
                const innerHTML = data.dirs.map((dir) => dir
                    .files
                    .filter((file) => file.endsWith(".JPG"))
                    .map((file) => 
                      `<img class="img" width="${width}" height="${height}" src="/v1/photos/${dir.name}/${file}?size=${size}">`
                    ).join('')).join('');

                document.getElementById("thumbnails").innerHTML = innerHTML;
              });
              return false;
            }
          </script>
          <div class="container">
            <div id="thumbnails">
            </div>
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
    _proxy(from_socket: camera, to_conn: conn)
  end

  def photos(conn)
    camera = TCPSocket.new(@ricoh_ip, 80)
    path = conn.request_path
    if conn.query_string
      path << "?"
      path << conn.query_string
    end

    camera << "GET #{path} HTTP/1.0\r\n" 
    camera << "Host: #{@ricoh_ip}\r\n" 
    camera << "\r\n"
    camera.flush
    _proxy(from_socket: camera, to_conn: conn)
  end

  def props(conn)
    camera = TCPSocket.new(@ricoh_ip, 80)
    camera << "GET /v1/props HTTP/1.0\r\n" 
    camera << "Host: #{@ricoh_ip}\r\n" 
    camera << "\r\n"
    camera.flush
    _proxy(from_socket: camera, to_conn: conn)
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

  private def _proxy(from_socket:, to_conn:)
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

if RUBY_ENGINE != 'ruby' or __FILE__ == $0
  server = HTTPServer.new(host: '127.0.0.1', port: 8080, handler: App.new)
  puts "[Point your browser at: http://localhost:8080/ or http://localhost:8080/browser]"
  server.start
end
