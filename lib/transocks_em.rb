require 'socket'
require 'eventmachine'
require 'logging'

include Logging.globally

module TransocksEM
  OPSYS = `uname -s`.chomp

  def self.config
    unless defined?(@@config)
      @@config = {}
    end
    @@config
  end

  class EM::Connection
    def orig_sockaddr
      addr = get_sock_opt(Socket::SOL_IP, 80) # Socket::SO_ORIGINAL_DST
      _, port, host = addr.unpack("nnN")

      [host, port]
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

  class TransocksTCPServer < EM::Connection
    attr_accessor :closed

    def initialize(ipfw_natd_style = false)
      @ipfw_natd_style = ipfw_natd_style
    end

    def post_init
      return  if @ipfw_natd_style

      orig_host, orig_port = orig_sockaddr
      orig_host = [orig_host].pack("N").unpack("CCCC")*'.'

      proxy_to orig_host, orig_port
    end

    def receive_data(data)
      @buf ||= ''
      @buf << data
      if @buf.gsub!(/\[DEST (\d+\.\d+\.\d+\.\d+) (\d+)\] *\n/m, '')
        orig_host, orig_port = $1, $2.to_i
        proxy_to orig_host, orig_port
        @proxied.send_data @buf
      end
    end

    def proxy_target_unbound
      close_connection
    end

    def unbind
      self.closed = true
      @proxied.close_connection_after_writing  if @proxied
    end

    private

    def config
      TransocksEM.config
    end

    def proxy_to(orig_host, orig_port)
      logger.info { "connecting to #{orig_host}:#{orig_port}" }

      @proxied = EM.connect(config[:connect_host], config[:connect_port], TransocksClient, self, orig_host, orig_port)
      proxy_incoming_to @proxied  unless @proxied.closed
    end
  end
end

require 'transocks_em/command'

