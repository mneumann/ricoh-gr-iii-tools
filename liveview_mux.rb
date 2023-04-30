#
# Multiplexes Ricoh GR III liveview MJPEG to multiple clients.
#
# Somehow this shows less lag when OBS Studio connects against it, as when OBS
# directly connects against Ricoh GR III with WIFI on
# (http://192.168.0.1/v1/liveview).
#
# Starts a HTTP server on localhost:3333. Just point your browser to 
# http://localhost:3333/ and you'll see the liveview.
#
# It also limits FPS to ARGV[0].
#
# In OBS Studio, set format to "mjpeg".
#

require 'socket'
require 'stringio'

class FrameDecoder
  def initialize(boundary_marker:, frame_handler:)
    @boundary_marker = boundary_marker
    @frame_handler = frame_handler
    @buffer = String.new
  end

  def feed_data(data)
    @buffer << data

    if pos = @buffer.index(@boundary_marker)
      handle_chunk(@buffer[0...pos])
      @buffer = @buffer[pos+@boundary_marker.size..]
    end
  end

  private def handle_chunk(chunk)
    return if chunk.empty?
    io = StringIO.new(chunk)
    http_headers = parse_http_headers(io)
    frame = io.read
    @frame_handler.call(frame, http_headers) unless frame.empty?
  end

  private def parse_http_headers(io)
    http_headers = Hash.new { [] }
    loop do
      header = io.readline.chomp
      break if header.empty?
      key, value = header.split(':').map(&:strip)
      key.downcase!
      http_headers[key] = value
    end
    return http_headers
  end
end

class FrameHandler
  def initialize(fps: , listeners:)
    @fps = fps
    @listeners = listeners
    @start = Time.now.to_f
    @frame_no = 0
  end

  def call(frame, http_headers)
    elapsed = Time.now.to_f - @start
    fps = (@frame_no.to_f / elapsed)
    if fps <= @fps
      @frame_no += 1
      send_frame(frame)
    end
    STDERR.puts "fps: #{fps}"
  end

  private def send_frame(frame)
    for listener in @listeners
      begin
        listener << "--boundary\r\n"
        listener << "Content-Type: image/jpeg\r\n\r\n"
        listener << frame
        listener.flush
      rescue
      end
    end
  end
end


FPS = (ARGV[0] || "24").to_i
BUF_SIZE = (ARGV[1] || "8").to_i * 1024

$listeners = []

$server = Thread.new do
  serv = TCPServer.new('127.0.0.1', 3333)
  loop do
    sock = serv.accept
    Thread.new(sock) do |sock|
      begin
        loop do
          line = sock.readline.chomp
          # STDERR.puts line
          break if line.empty?
        end

        sock << "HTTP/1.1 200 OK\r\n"
        sock << "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
        sock << "Expires: 0\r\n"
        sock << "Pragma: no-cache\r\n"
        sock << "Content-Type: multipart/x-mixed-replace; boundary=boundary\r\n"
        sock << "\r\n"

        $listeners << sock
        sleep rescue nil
      ensure
        $listeners.delete(sock)
        sock.close rescue nil
      end
    end
  end
end


s = TCPSocket.new('192.168.0.1', 80)
s << "GET /v1/liveview HTTP/1.0\r\n"
s << "\r\n"
s.flush

loop do
  line = s.readline.chomp
  STDERR.puts line
  break if line.empty?
end

frame_handler = FrameHandler.new(fps: FPS, listeners: $listeners)
frame_decoder = FrameDecoder.new(boundary_marker: "--boundary\r\n", frame_handler: frame_handler) 

loop do
  frame_decoder.feed_data(s.read(BUF_SIZE))
end
