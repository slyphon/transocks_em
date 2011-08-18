require 'tempfile'

module TransocksEM
  class IPFWTweaker
    DEFAULT_START_RULE_NUM = 1_000
    DEFAULT_NAT_ENCODING = 'encode_tcp_stream'.freeze

    OFFSET = 10
    DIVERT_PORT = 4000
    IPFW_SET_NUM = 7

    IPFW_BIN = '/sbin/ipfw' # Darwin & FreeBSD

    attr_reader :start_rule_num, :offset, :ipfw_set_num, :added_rule_nums, :divert_port, :nat_encoding

    def initialize(opts={})
      @start_rule_num   = opts.fetch(:start_rule_num, DEFAULT_START_RULE_NUM)
      @cur_rule_num     = @start_rule_num

      @offset           = opts.fetch(:offset, OFFSET)
      @divert_port      = opts.fetch(:divert_port, DIVERT_PORT)
      @ipfw_set_num     = opts.fetch(:ipfw_set_num, IPFW_SET_NUM)
      @nat_encoding     = opts.fetch(:nat_encoding, DEFAULT_NAT_ENCODING)

      @added_rule_nums  = []
      @natd_pid         = nil
      @natd_config_tmpfile  = nil
      validate!
    end

    def transocks_port
      TransocksEM.config[:listen_port]
    end

    # Diverts the given ports to SOCKS via ipfw and natd. after this has been
    # called once, you must reset the rules before calling it again, or an
    # error will occur
    def divert_to_socks(*ports)
      clear_state!
      add_ipfw_diversion_rules!(ports)
      setup_natd!(ports)
    end

    def clear_state!
      clear_ipfw_rules!
      kill_natd!
    end

    def add_ipfw_diversion_rules!(ports)
      if freebsd?
        if `kldstat`.split("\n").grep(/ipdivert\.ko$/).empty?
          sh("sudo kldload ipdivert")
        end
      end

      ipfw *%W[set disable #{ipfw_set_num}]
      ipfw *%W[add #{cur_rule_num} set #{ipfw_set_num} divert #{divert_port} tcp from 127.0.0.1 #{transocks_port} to me in]
      ipfw *%W[add #{cur_rule_num} set #{ipfw_set_num} divert #{divert_port} tcp from me to any #{ports.join(',')} out]
      ipfw *%W[set enable #{ipfw_set_num}]

      logger.debug do
        rules = `sudo ipfw list`
        "ipfw rules: #{rules}"
      end
    end

    def setup_natd!(ports)
      kill_natd!

      @natd_config_tmpfile = tmp = Tempfile.new('natdrulez')

      tmp.puts(<<-EOS)
port #{divert_port} 
log yes
interface lo0 
proxy_only yes
      EOS

      ports.each do |port|
        tmp.puts %Q[proxy_rule type #{nat_encoding} port #{port} server 127.0.0.1:#{transocks_port}]
      end

      tmp.fsync

      tmp.rewind
      config = tmp.read

      logger.debug { "natd config: \n#{config}" }

      cmd = %W[sudo #{natd_bin} -f #{tmp.path}]

      opts = {
        :chdir => '/',
        :in  => '/dev/null',
        :out => [:child, :err],
        :err => '/dev/null',
      }

      if TransocksEM.debug?
        cmd << '-v'
        opts[:err] = '/tmp/natd.log'
      end

      cmd << opts

      logger.debug { "spawning natd: #{cmd.inspect}" }

      @natd_pid = Process.spawn(*cmd)

      logger.debug { "launched natd pid: #{@natd_pid}" } 
    end

    def clear_ipfw_rules!
      sh(*%W[sudo ipfw delete set #{ipfw_set_num}])
    rescue RuntimeError
    end

    def kill_natd!
      if @natd_config_tmpfile
        @natd_config_tmpfile.close
        @natd_config_tmpfile = nil
      end

      if @natd_pid
        sh(*%W[sudo kill -9 #{@natd_pid}])
        Process.waitpid2(@natd_pid)
        @natd_pid = nil
      end
    end

    protected
      def ipfw(*args)
        cmd = ['sudo', IPFW_BIN]
        
        cmd << '-q' unless TransocksEM.debug?

        cmd += args

        sh(*cmd)
      end

      def sh(*cmd)
        logger.debug { "running command: #{cmd.join(' ')}" }

        system(*cmd).tap do |bool|
          raise "command: #{cmd.join(' ')} failed with status: #{$?.inspect}" unless bool
        end
      end
      
      def natd_bin
        @natd_bin ||= (
          case OPSYS
          when 'Darwin'
            '/usr/sbin/natd'
          when 'FreeBSD'
            '/sbin/natd'
          else
            raise "don't know about natd on opsys: #{OPSYS}"
          end
        )
      end

      def freebsd?
        OPSYS == 'FreeBSD'
      end

      def cur_rule_num
        orig = @cur_rule_num
        @added_rule_nums << orig
        @cur_rule_num += @offset
        orig
      end

      def validate!
        raise ArgumentError, "nat_encoding must be encode_ip_hdr or encode_tcp_stream, not #{@nat_encoding.inspect}" unless @nat_encoding =~ /^(encode_ip_hdr|encode_tcp_stream)$/
      end
  end
end

