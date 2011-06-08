require 'syslog'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/kernel/reporting'
require 'aws'

module Epas

  class UnavailableEC2Credentials < StandardError; end
  class UnavailablePuppet < StandardError; end

  class AutoSigner

    # Creates a new auto_signer object tied to the specific ec2 account and regions provided.
    #
    # ==== Attributes
    #
    # * +file+ - Path to a file containing only the EC2 id and secret access_keys in the two first lines and in this order. Defaults to "~/.awssecret".
    # * +regions+ - Array containing all EC2 regions to check, defaults to all available.
    #
    # ==== Examples
    #
    #    Epas::Autosigner.new
    #    Epas::AutoSigner.new myfile, [ 'eu-west-1', 'eu-east-1']
    def initialize(file = "~/.awssecret", regions = [])
      raise UnavailablePuppet unless command?('puppet') && command?('puppetca')
      @aws_id, @aws_key        = read_aws_credentials(file)
      @regions                 = regions.blank? ? get_all_ec2_regions : regions
      @awaiting_sign_instances = get_awaiting_sign_instances
    end

    # Signs all pending requests in puppet initiated by ec2 machines.
    def sign_ec2_instance_requests!
      # TODO: Add logging to syslog
      unless @awaiting_sign_instances.blank?
        get_all_ec2_instances_ids.each do |instance_id|
          @awaiting_sign_instances.each do |hostname|
            sign_instance(hostname) if hostname.match /#{instance_id}/
          end
        end
      end
    end

    private

    def read_aws_credentials(file)
      file = File.expand_path(file)
      raise UnavailableEC2Credentials unless File.exists?(file)
      id, key = File.read(file).split("\n")
      raise UnavailableEC2Credentials if id.blank? || key.blank?
      [id, key]
    end

    def sign_instance(hostname)
      # TODO: Run with sudo if not root
      result = system("puppet cert --sign #{hostname}")
      if result
        log "Server with hostname: #{hostname} signed succesfully."
      else
        log "Failed to sign server with hostname: #{hostname}"
      end
    end

    def get_awaiting_sign_instances
      # TODO: Run with sudo if not root
      `puppetca --list`.split("\n")
    end

    def get_all_ec2_regions
      %w(eu-west-1 us-east-1 ap-northeast-1 us-west-1 ap-southeast-1)
    end

    def get_all_ec2_instances_ids
      instances = @regions.map do |region|
       silence_stream STDOUT do
          Aws::Ec2.new(@aws_id, @aws_key, :region => region).describe_instances
        end
      end.flatten
      ids = instances.map { |i| i[:aws_instance_id] }
    end

    def command?(command)
      system("which #{command} > /dev/null 2>&1")
    end

    def log(message)
      # $0 is the current script name
      Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning message }
    end

  end

end
