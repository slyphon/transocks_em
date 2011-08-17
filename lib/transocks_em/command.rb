module TransocksEM
  class Command

    USAGE = <<-EOS
Usage: transsocks_em.rb <proxy_to_host> <proxy_to_port> <listen_port> [natd]

natd - puts daemon in ipfw/natd bsd mode rather than linux iptables SO_ORIGINAL_DST mode,
      aka: get the original dest addr/port from the TCP stream rather than from getsockopt.
      Current issue with natd mode is that the original addr wont be sent until the connection
      sends some initial data (this makes it incompatible with certain protocols, SSH for example).
      This is the default for Darwin (checked using uname -s).

    EOS

    def self.main
      new.main
    end

    def main
      if ARGV.size < 3
        $stderr.puts USAGE
        exit 1
      end

      host, port, listen = ARGV[0,3]

      config = TransocksEM.config

      config.merge({
        :connect_host => host,
        :connect_port => port.to_i, 
        :listen_port  => listen.to_i,
      })

      Logging.backtrace(true)

      Logging.logger.root.tap do |root|
        root.level = :debug
        root.add_appenders(Logging.appenders.stderr)
      end

      if (ARGV[3] == 'natd') or (TransocksEM::OPSYS =~ /^(?:Darwin|FreeBSD)$/)
        config[:natd] = true
        logger.info { "set natd mode" }
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
    end
  end
end

