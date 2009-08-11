require 'socket'
require 'rubygems'
require 'eventmachine'

class EM::P::Socks4 < EM::Connection
  def initialize(host, port)
    @host, @port = host, port
    @buffer = ''
    setup_methods
  end

  def setup_methods
    class << self
      def post_init; socks_post_init; end
      def receive_data(*a); socks_receive_data(*a); end
    end
  end

  def restore_methods
    class << self
      remove_method :post_init
      remove_method :receive_data
    end
  end

  def socks_post_init
    header = [4, 1, @port, @host, 0].pack("ccnNc")
    send_data(header)
  end

  def socks_receive_data(data)
    @buffer << data
    return  if @buffer.size < 8

    header_resp = @buffer.slice! 0, 8
    _, r = header_resp.unpack("cc")
    if r != 90
      puts "rejected by socks server!"  
      close_connection
      return
    end

    restore_methods

    post_init
    receive_data(@buffer)  unless @buffer.empty?
  end
end

class TransocksClient < EM::P::Socks4
  attr_accessor :closed

  def initialize(proxied, host, port)
    @proxied = proxied
    super(host, port)
  end

  def receive_data(data)
    @proxied.send_data(data)
    proxy_incoming_to @proxied  unless @proxied.closed
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    self.closed = true
    @proxied.close_connection_after_writing
  end
end

class TransocksServer < EM::Connection
  attr_accessor :closed
  def post_init
    orig_host, orig_port = orig_socket
    addr = [orig_host].pack("N").unpack("CCCC")*'.'
    puts "connecting to #{addr}:#{orig_port}"
    @proxied = EM.connect('127.1', 6666, TransocksClient, self, orig_host, orig_port)
    proxy_incoming_to @proxied  unless @proxied.closed
  end

  def proxy_target_unbound
    close_connection
  end

  def unbind
    self.closed = true
    @proxied.close_connection_after_writing
  end

  def orig_socket
    addr = get_sock_opt(Socket::SOL_IP, 80) # Socket::SO_ORIGINAL_DST
    _, port, host = addr.unpack("nnN")

    [host, port]
  end
end

EM.run do
  EM.error_handler { puts $!, $@ }
  EM.start_server '127.1', '1212', TransocksServer
end
