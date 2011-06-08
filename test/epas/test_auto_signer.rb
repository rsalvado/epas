require 'helper'
require 'tempfile'
require 'aws'
require 'syslog'

class TestAutoSigner < Test::Unit::TestCase

  def setup
    @awaiting_sign_instances = %w( appserver.i-qwerty.example.com dbserver.i-uiop.com ).join("\n")
    @eu_instances = [ { :aws_instance_id => 'i-qwerty' } ]
    @us_instances = [ { :aws_instance_id => 'i-uiop' } ]
    @regions = %w(eu-west-1 us-east-1)
    @instances_by_region = {
      @regions[0] => @eu_instances,
      @regions[1] => @us_instances
    }
    @aws_id = 'myid'
    @aws_key = 'mykey'
    @credentials_file = Tempfile.new('credentials')
    @credentials_file.write "#{@aws_id}\n#{@aws_key}"
    @credentials_file.close
    Epas::AutoSigner.any_instance.expects(:system).with("which puppet > /dev/null 2>&1").returns(true)
    Epas::AutoSigner.any_instance.expects(:system).with("which puppetca > /dev/null 2>&1").returns(true)
  end

  def test_should_raise_exception_when_ec2_credentials_unavailable
    assert_raise Epas::UnavailableEC2Credentials do
      unexistant_file = '1232wqewqdscdslkdsakdowqowqoewqoewqieoiwqoewq'
      Epas::AutoSigner.new(unexistant_file)
    end
  end

  def test_should_raise_exception_when_null_credentials
    file = Tempfile.open('credentials')
    assert_raise Epas::UnavailableEC2Credentials do
      Epas::AutoSigner.new(file.path)
    end
  end

  def test_should_raise_exception_when_invalid_credentials
    Epas::AutoSigner.any_instance.expects(:`).with('puppetca --list').returns(@awaiting_sign_instances)
    assert_raise Aws::AwsError do
      as = Epas::AutoSigner.new(@credentials_file.path)
      as.sign_ec2_instance_requests!
    end
  end

  def test_should_sign_our_ec2_instances_certificate_requests
    with_ec2_testcase
  end

  def test_should_log_when_signing_instances
    with_ec2_testcase do
      Syslog.expects(:open).twice
    end
  end

  private

  def with_ec2_testcase
    @instances_by_region.each do |region, instances|
      Aws::Ec2.expects(:new).with(@aws_id, @aws_key, :region => region).returns(stub(:describe_instances => instances))
    end

    Epas::AutoSigner.any_instance.expects(:`).with('puppetca --list').returns(@awaiting_sign_instances)

    Epas::AutoSigner.any_instance.expects(:system).with("puppet cert --sign appserver.i-qwerty.example.com").once
    Epas::AutoSigner.any_instance.expects(:system).with("puppet cert --sign dbserver.i-uiop.com").once
    yield if block_given?
    autosigner = Epas::AutoSigner.new(@credentials_file.path, @regions)
    autosigner.sign_ec2_instance_requests!
  end

end
