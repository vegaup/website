require 'webrick'
require 'erb'
require 'socket'
require 'base64'
require 'digest/sha1'
require 'listen'

class WebSocketServer
  def initialize(port = 8081, host = 'localhost')
    @server = TCPServer.new(host, port)
    @clients = []
    puts " • WebSocket server running on ws://#{host}:#{port}"
  end

  def run
    Thread.new do
      loop do
        Thread.start(@server.accept) do |client|
          handle_connection(client)
        end
      end
    end
  end

  def notify_reload
    @clients.each do |client|
      begin
        client.write(create_websocket_frame("reload"))
      rescue
        @clients.delete(client)
      end
    end
  end

  private

  def handle_connection(client)
    handshake(client)
    @clients << client
  rescue => e
    puts "WebSocket Error: #{e.message}"
    client.close
  end

  def handshake(client)
    request = client.readpartial(2048)
    key = request.match(/Sec-WebSocket-Key: (.+)\r\n/)[1]
    magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    accept = Base64.strict_encode64(Digest::SHA1.digest(key + magic))
    
    response = [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Accept: #{accept}",
      "\r\n"
    ].join("\r\n")
    
    client.write(response)
  end

  def create_websocket_frame(message)
    [0x81, message.bytesize, message].pack("CCA#{message.bytesize}")
  end
end

class NineServer < WEBrick::HTTPServer
  def initialize(options = {})
    @expose = options.delete(:expose) || false
    super(options)
  end
end

class RequestHandler < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(request, response)
    path = request.path
    path = '/index.html' if path == '/'

    # Try to serve the file from root directory
    if File.exist?(path)
      response.body = File.read(path)
      response.content_type = get_content_type(path)
      return
    end

    # If file doesn't exist, serve 404
    serve_404(response)
  rescue => e
    response.status = 500
    response.body = "Error: #{e.message}"
  end

  private

  def serve_404(response)
    response.status = 404
    if File.exist?('404.html')
      response.body = File.read('404.html')
    else
      response.body = '404 Not Found'
    end
    response.content_type = 'text/html'
  end

  def inject_live_reload(content)
    return content if @server.config[:prod]
    
    ws_host = @server.config[:expose] ? `hostname -I`.strip : 'localhost'
    live_reload_script = <<-SCRIPT
      <script>
        const ws = new WebSocket(`ws://#{ws_host}:8081`);
        ws.onmessage = function(event) {
          if (event.data === "reload") {
            console.log("File changed! Reloading...");
            window.location.reload();
          }
        };
      </script>
    SCRIPT
    
    content.sub('</body>', "#{live_reload_script}</body>")
  end

  def get_content_type(path)
    case File.extname(path)
    when '.html' then 'text/html'
    when '.js'   then 'application/javascript'
    when '.css'  then 'text/css'
    when '.png'  then 'image/png'
    when '.jpg'  then 'image/jpeg'
    else 'text/plain'
    end
  end
end

expose = ARGV.include?('--expose')
prod = ARGV.include?('--prod')

unless prod
  ws_server = WebSocketServer.new(
    8081,
    expose ? '0.0.0.0' : 'localhost'
  )
  ws_server.run
end

# Create and start the HTTP server
server = NineServer.new(
  Port: 8080,
  Host: expose ? '0.0.0.0' : 'localhost',
  expose: expose,
  prod: prod,
  AccessLog: []
)

server.mount '/', RequestHandler

# Set up file watcher only if not in prod mode
unless prod
  listener = Listen.to('.') do |modified, added, removed|
    puts "Files changed: #{(modified + added + removed).join(', ')}"
    ws_server.notify_reload
  end
  listener.start
end

# Print banner
puts "╔══════════════════════════════╗"
puts "║        CloudNine Server      ║"
puts "║         By VegaUp Team       ║"
puts "╚══════════════════════════════╝"
puts "Cloud listening..."
puts " • Device: http://localhost:8080"
puts " • Mode: #{prod ? 'Production' : 'Development'}"
if expose
  ip = `hostname -I`.strip
  puts " • Network: http://#{ip}:8080"
  puts " ⚠️  Warning: Server exposed to network, proceed with caution!"
else
  puts " • Network: Use '--expose' flag to expose server to network"
end

# Handle graceful shutdown
trap('INT') { server.shutdown }

# Start the server
server.start
