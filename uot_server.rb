require 'rubygems'
require 'eventmachine'

class UOTServer < EM::Connection
  include EM::P::ObjectProtocol

  def initialize
    super
    @mapping = {}
  end

  def receive_object(data)
    host, port, data = data
    outgoing_connection = @mapping[[host, port]] ||= EM.open_datagram_socket('0', 0, UDPConnection, self, host, port)
    outgoing_connection.send_datagram data, host, port
  end

  def unbind
    p :control_conn_dropped
  end
end

class UDPConnection < EM::Connection
  def initialize(server, host, port)
    super
    @server, @host, @port = server, host, port
  end

  def receive_data(data)
    @server.send_object [@host, @port, data]
  end
end

listen_port = ARGV.first

EM.run do
  EM.error_handler { puts $!, $@ }
  EM.start_server '0', listen_port, UOTServer
end
