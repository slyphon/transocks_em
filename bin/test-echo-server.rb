#!/usr/bin/env ruby

require 'rubygems'
require 'logging'
require 'time'
require 'date'
require 'ruby-debug'

$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__)).uniq!

require 'transocks_em'

include Logging.globally

Logging.logger.root.tap do |log|
  log.level = :debug
  log.add_appenders(Logging.appenders.stderr)
end

class SimpleEchoServer
  def initialize
    @serv = nil
    @ipfw_tweaker = TransocksEM::IPFWTweaker.new(:nat_encoding => 'encode_ip_hdr', :start_rule_num => 10)
  end

  def timestamp
    Time.now.strftime("%Y-%m-%d %H:%M:%S.%N")
  end

  def brute_force_sock_opts(s)
    (0..255).to_a.each do |n|
      begin
        v = s.getsockopt(:IP, n)
        logger.info { "sock_opt #{n} #{v.inspect}" }
      rescue 
      end
    end
  end

  def main
    TransocksEM.config.merge!({
      :connect_host => 'localhost',
      :connect_port => 1080,
      :listen_port  => 1081,
      :debug        => true,
    })

    logger.debug { "listening on 1081" }

    @ipfw_tweaker.divert_to_socks(2000)

    @serv = TCPServer.new('127.0.0.1', 1081)

    while true
      sock = @serv.accept

      begin
        logger.debug{ "accepted connection from: #{sock.peeraddr(false)}" }

        brute_force_sock_opts(sock)

        msg = sock.read(1024)

        sock.puts("#{timestamp}: #{msg}")
      ensure
        sock.close
      end
    end

  rescue Interrupt
    logger.warn { "exiting on HUP" }
  ensure
    @ipfw_tweaker.clear_state!
  end
end


SimpleEchoServer.new.main if __FILE__ == $0

