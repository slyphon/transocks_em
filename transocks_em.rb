require 'socket'
require 'rubygems'
require 'eventmachine'

class EM::P::Socks4 < EM::Connection
  def initialize(proxied_conn, host, port)
    @proxied, @host, @port = proxied_conn, host, port
    @buffer = ''
  end

  def post_init
    header = [4, 1, @port, @host, 0].pack("ccnNc")
    send_data(header)
  end

  def receive_data(data)
    @buffer << data
    return  if @buffer.size < 8

    header_resp = @buffer.slice! 0, 8
    _, r = header_resp.unpack("cc")
    raise "rejected by socks server!"  if r != 90

    @proxied.send_data(@buffer)
    proxy_incoming_to @proxied
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    @proxied.close_connection_after_writing
  end
end

class TransocksServer < EM::Connection
  def post_init
    orig_host, orig_port = orig_socket
    addr = [orig_host].pack("N").unpack("CCCC")*'.'
    puts "connecting to #{addr}:#{orig_port}"
    @proxied = EM.connect('127.1', 6666, EM::P::Socks4, self, orig_host, orig_port)
    proxy_incoming_to @proxied
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    @proxied.close_connection_after_writing
  end

  def orig_socket
    $s ||= []
    $s << s = Socket.for_fd(get_fd)
    addr = s.getsockopt(Socket::SOL_IP, 80) # Socket::SO_ORIGINAL_DST
    _, port, host = addr.unpack("nnN")

    [host, port]
  end
end

EM.run do
  EM.error_handler { puts $!, $@ }
  EM.start_server '127.1', '1212', TransocksServer
end
