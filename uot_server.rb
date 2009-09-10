require 'rubygems'
require 'eventmachine'

class UOTServer < EM::Connection
  include EM::P::ObjectProtocol

  def receive_object(data)
    host, port, data = data
    $outgoing_connection.send_datagram data, host, port
  end
end

class UDPConnection < EM::Connection
  def receive_data(data)
    port, host = Socket.unpack_sockaddr_in(get_peername)
    $server.send_object [host, port, data]
  end
end

listen_port = ARGV.first

EM.run do
  EM.error_handler { puts $!, $@ }
  $server = EM.start_server '0', listen_port, UOTServer
  $outgoing_connection = EM.open_datagram_socket '0', 0, UDPConnection
end
