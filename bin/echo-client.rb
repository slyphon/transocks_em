#!/usr/bin/env ruby

require 'socket'

if ARGV.length < 2
  $stderr.puts "usage: #{File.basename($0)} host port"
  exit 1
end

TCPSocket.open(ARGV[0], ARGV[1].to_i) do |sock|
  msg = $stdin.read
  sock.write(msg)
  puts sock.read
end

