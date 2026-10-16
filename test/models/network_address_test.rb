require "test_helper"

class NetworkAddressTest < ActiveSupport::TestCase
  test "private, loopback, link local, unspecified and reserved addresses are private, and a public one is not" do
    %w[10.0.0.1 172.16.0.1 192.168.1.1 127.0.0.1 ::1 169.254.169.254 fe80::1 0.0.0.0 :: 100.100.100.200 192.0.0.8 198.18.0.1
       224.0.0.1 240.0.0.1 ff02::1 ::ffff:10.0.0.1].each do |address|
      assert NetworkAddress.private_ip?(IPAddr.new(address)), "#{address} should be private"
    end
    assert_not NetworkAddress.private_ip?(IPAddr.new("93.184.216.34"))
    assert_not NetworkAddress.private_ip?(IPAddr.new("2606:2800:220:1:248:1893:25c8:1946"))
  end

  test "an IPv6 address carrying a private IPv4 one, through NAT64, 6to4 or the old compatible form, is private too" do
    %w[64:ff9b::a00:1 64:ff9b::a9fe:a9fe 2002:a00:1:: 2002:7f00:1:: ::a00:1 ::7f00:1].each do |address|
      assert NetworkAddress.private_ip?(IPAddr.new(address)), "#{address} should be private"
    end
    assert_not NetworkAddress.private_ip?(IPAddr.new("64:ff9b::5db8:d822")), "NAT64 of a public address stays public"
  end

  test "an AI account's API base on the shared cloud range is refused on a hosted build" do
    assert_equal "The API base URL is on a private network, which Firefight does not reach",
                 AiAccountAddress.refusal("http://100.100.100.200/v1", private_allowed: false)
    assert_nil AiAccountAddress.refusal("http://100.100.100.200/v1", private_allowed: true)
  end
end
