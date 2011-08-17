module TransocksEM
  class Command
    USAGE = <<-EOS
Usage: transsocks_em.rb [opts] <proxy_to_host> <proxy_to_port> <listen_port>

--natd puts daemon in ipfw/natd bsd mode rather than linux iptables SO_ORIGINAL_DST mode,
       aka: get the original dest addr/port from the TCP stream rather than
       from getsockopt.  Current issue with natd mode is that the original addr
       wont be sent until the connection sends some initial data (this makes it
       incompatible with certain protocols, SSH for example).  This is the
       default for Darwin (checked using 'uname -s').


    EOS

    def self.main
      new.main
    end

    def initialize
      @ipfw_tweaker = IPFWTweaker.new
      @set_ipfw_state = false
      @divert_ports = []
    end

    def config
      TransocksEM.config
    end

    def optparser
      @optparser ||= OptionParser.new do |o|
        o.banner = USAGE
        o.on('--natd', 'see description above') { config[:natd] = true }
        o.on('-P', '--ports a,b,c', Array, 'the ports to divert to socks (mandatory)') do |a|
          @divert_ports = a.map { |n| Integer(n) }
        end
        o.on('-h', '--help', "you're reading it") { help! }
      end
    end

    def help!
      $stderr.puts optparser
      exit 1
    end

    def main
      optparser.parse!(ARGV)

      help! if @divert_ports.empty? or (ARGV.size < 3)

      host, port, listen = ARGV[0,3]

      config.merge!({
        :connect_host => host,
        :connect_port => port.to_i, 
        :listen_port  => listen.to_i,
      })

      Logging.backtrace(true)

      Logging.logger.root.tap do |root|
        root.level = :debug
        root.add_appenders(Logging.appenders.stderr)
      end

      logger.debug { "using config: #{config.inspect}" }

      if (ARGV[3] == 'natd') or (TransocksEM::OPSYS =~ /^(?:Darwin|FreeBSD)$/)
        config[:natd] = true
        logger.info { "set natd mode" }
        @set_ipfw_state = true
        @ipfw_tweaker.divert_to_socks(*@divert_ports)
      end

      %w[INT TERM].each do |sig|
        Kernel.trap(sig) do
          logger.info { "trapped signal #{sig}, shutting down" }
          EM.next_tick { EM.stop_event_loop }
        end
      end

      EM.run do
        logger.info { "started event loop" }

        EM.error_handler do |e|
          logger.error { e }
        end

        EM.start_server '127.0.0.1', config[:listen_port], TransocksTCPServer, config[:natd]
      end

    ensure
      @ipfw_tweaker.clear_state! if @set_ipfw_state
    end
  end
end

