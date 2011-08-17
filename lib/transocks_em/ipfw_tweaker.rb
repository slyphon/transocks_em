require 'tempfile'

module TransocksEM
  class IPFWTweaker
    DEFAULT_START_RULE_NUM = 10_000
    OFFSET = 10
    DIVERT_PORT = 4000
    IPFW_SET_NUM = 7

    IPFW_BIN = '/sbin/ipfw' # Darwin & FreeBSD

    attr_reader :start_rule_num, :offset, :ipfw_set_num, :added_rule_nums, :divert_port

    def initialize(opts={})
      @start_rule_num   = opts.fetch(:start_rule_num, DEFAULT_START_RULE_NUM)
      @cur_rule_num     = @start_rule_num

      @offset           = opts.fetch(:offset, OFFSET)
      @divert_port      = opts.fetch(:divert_port, DIVERT_PORT)
      @ipfw_set_num     = opts.fetch(:ipfw_set_num, IPFW_SET_NUM)
      @added_rule_nums  = []
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
      Tempfile.open('ipfwrulez', Dir.tmpdir, :encoding => 'utf8')  do |tmp|
        tmp.puts <<-EOS
#{cur_rule_num} set #{ipfw_set_num} add divert #{divert_port} tcp from 127.0.0.1 #{transocks_port} to me in
#{cur_rule_num} set #{ipfw_set_num} add divert #{divert_port} from me to any #{ports.join(',')} out
        EOS

        tmp.fsync

        sh "sudo #{IPFW_BIN} #{tmp.path}"
      end
    end

    def setup_natd!(ports)
      kill_natd!

      Tempfile.open('natdrulez') do |tmp|
        tmp.puts(<<-EOS)
port #{divert_port} 
interface lo0 
proxy_only yes
        EOS

        ports.each do |port|
          tmp.puts %Q[-proxy_rule type encode_tcp_stream port #{port} server 127.0.0.1:#{transocks_port}]
        end
      end

      cmd = %W[sudo #{natd_bin} -f #{tmp.path}]

      sh(*cmd)
    end

    def clear_ipfw_rules!
      sh(%W[sudo ipfw delete set #{ipfw_set_num}])
    rescue RuntimeError
    end

    def kill_natd!
      sh "sudo killall -9 #{natd_bin}"
    rescue RuntimeError
    end

    protected
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

      def cur_rule_num
        orig = @cur_rule_num
        @added_rule_nums << orig
        @cur_rule_num += @offset
        orig
      end
  end
end

