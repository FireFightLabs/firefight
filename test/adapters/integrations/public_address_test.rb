require "test_helper"

module Integrations
  class PublicAddressTest < ActiveSupport::TestCase
    test "a public host is reached at the address checked, and a private one only when an operator allowed it" do
      Addrinfo.stubs(:getaddrinfo).with("db.example.com", nil, nil, :STREAM).returns([ Addrinfo.tcp("93.184.216.34", 0) ])
      assert_equal [ "93.184.216.34", false ], PublicAddress.check!("db.example.com", provider_key: "postgresql").then { |checked| [ checked.ip.to_s, checked.private ] }

      Addrinfo.stubs(:getaddrinfo).with("cluster.internal", nil, nil, :STREAM).returns([ Addrinfo.tcp("100.64.1.2", 0) ])
      error = assert_raises(PublicAddress::Refused) { PublicAddress.check!("cluster.internal", provider_key: "kubernetes") }
      assert_equal "cluster.internal is on a private network, which Firefight does not connect to.", error.message

      ENV["INTEGRATION_KUBERNETES_PRIVATE_HOSTS"] = "100.64.0.0/10"
      assert PublicAddress.check!("cluster.internal", provider_key: "kubernetes").private
    ensure
      ENV.delete("INTEGRATION_KUBERNETES_PRIVATE_HOSTS")
    end

    test "a host that cannot be found is said in words" do
      Addrinfo.stubs(:getaddrinfo).raises(SocketError)

      assert_equal "nowhere.example could not be found.", assert_raises(PublicAddress::Refused) { PublicAddress.check!("nowhere.example", provider_key: "gitlab") }.message
      assert_equal "INTEGRATION_GITLAB_PRIVATE_HOSTS", PublicAddress.allowed_env("gitlab")
    end
  end
end
