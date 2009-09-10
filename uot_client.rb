require 'rubygems'
require 'eventmachine'

class UOTClient < EM::Connection
  def receive_data(data)
    port, host = Socket.unpack_sockaddr_in(get_peername)

    dst_port = data.slice!(-2..-1).unpack("S").first
    dst_host = data.slice!(-4..-1).unpack("C4")*'.'

    $tunnel.mapping[[dst_host, dst_port]] = [host, port]
    $tunnel.send_object [dst_host, dst_port, data]
    print '>'; $stdout.flush
  end
end

class UOTTunnel < EM::Connection
  attr_accessor :mapping

  include EM::P::ObjectProtocol

  def initialize
    super
    @mapping = {}
  end

  def receive_object(data)
    host, port, data = data

    dst_host, dst_port = @mapping[[host, port]]
    if ! dst_host
      puts "unexpected packet received for #{host}:#{port}"
      return
    end

    $udp_connection.send_datagram data, dst_host, dst_port
    print '<'; $stdout.flush
  end

  def unbind
    p :control_conn_dropped
    reconnect
  end

  def reconnect
    @mapping.clear
    super $host, $port
  end
end

$host, $port, listen_port = ARGV[0], ARGV[1].to_i, ARGV[2]

EM.run do
  EM.error_handler { puts $!, $@ }
  $tunnel = EM.connect $host, $port, UOTTunnel
  $udp_connection = EM.open_datagram_socket '127.1', listen_port, UOTClient
end
