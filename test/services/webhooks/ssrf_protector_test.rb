require "test_helper"

class Webhooks::SsrfProtectorTest < ActiveSupport::TestCase
  test "blocks loopback addresses" do
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("127.0.0.1"))
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("::1"))
  end

  test "blocks private addresses" do
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("10.0.0.1"))
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("172.16.0.1"))
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("192.168.1.1"))
  end

  test "blocks link-local addresses" do
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("169.254.1.1"))
  end

  test "blocks carrier-grade NAT" do
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("100.64.0.1"))
  end

  test "blocks benchmark testing range" do
    assert Webhooks::SsrfProtector.blocked_address?(IPAddr.new("198.18.0.1"))
  end

  test "allows public addresses" do
    assert_not Webhooks::SsrfProtector.blocked_address?(IPAddr.new("8.8.8.8"))
    assert_not Webhooks::SsrfProtector.blocked_address?(IPAddr.new("93.184.216.34"))
  end

  test "resolve_public_ip returns nil for private-only hostname" do
    Resolv::DNS.any_instance.stubs(:each_address).yields(Resolv::IPv4.create("127.0.0.1"))
    assert_nil Webhooks::SsrfProtector.resolve_public_ip("evil.local")
  end

  test "resolve_public_ip returns public IP" do
    Resolv::DNS.any_instance.stubs(:each_address).yields(Resolv::IPv4.create("93.184.216.34"))
    assert_equal "93.184.216.34", Webhooks::SsrfProtector.resolve_public_ip("example.com")
  end
end
