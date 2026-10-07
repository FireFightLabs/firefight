require "test_helper"

module Integrations
  class KubernetesApiTest < ActiveSupport::TestCase
    include KubernetesTestHelper

    PUBLIC = IPAddr.new("203.0.113.10")

    setup do
      @ca = kubernetes_ca_pem
      PublicAddress.stubs(:resolve).returns(PUBLIC)
    end

    test "the CA is read from kubeconfig's base64, from PEM, and from PEM whose line breaks a text field dropped" do
      expected = OpenSSL::X509::Certificate.new(@ca).to_der

      [ Base64.strict_encode64(@ca), @ca, @ca.delete("\n") ].each do |pasted|
        assert_equal [ expected ], KubernetesApi.certificates(pasted).map(&:to_der)
      end
      assert_match "could not be read", KubernetesApi.refusal("https://cluster.example.com", "not a certificate")
      assert_match "holds no certificate", KubernetesApi.refusal("https://cluster.example.com", Base64.strict_encode64("hello"))
    end

    test "only an https address on a public network is used, unless an operator allowed the private one" do
      assert_match "must start with https://", KubernetesApi.refusal("http://cluster.example.com", @ca)
      assert_match "cannot carry a user", KubernetesApi.refusal("https://admin:x@cluster.example.com", @ca)
      assert_nil KubernetesApi.refusal("https://cluster.example.com:6443", @ca)

      PublicAddress.stubs(:resolve).returns(IPAddr.new("10.0.0.5"))
      assert_match "private network", KubernetesApi.refusal("https://cluster.internal", @ca)
      with_env(PublicAddress.allowed_env(KubernetesApi::PROVIDER_KEY) => "10.0.0.0/8") { assert_nil KubernetesApi.refusal("https://cluster.internal", @ca) }

      PublicAddress.stubs(:resolve).raises(PublicAddress::Refused, "nowhere.example.com could not be found.")
      assert_match "could not be found", KubernetesApi.refusal("https://nowhere.example.com", @ca)
    end

    test "a request goes to the address checked, trusts only the cluster's CA, and keeps the server's own path" do
      api = KubernetesApi.new(server: "https://rancher.example.com/k8s/clusters/c-1/", token: "sa-token", ca: @ca)
      Http.expects(:request).with do |uri, request, **options|
        uri.path == "/k8s/clusters/c-1/apis/apps/v1/namespaces/production/deployments" && uri.query == "limit=1" &&
          request["Authorization"] == "Bearer sa-token" && options[:ipaddr] == PUBLIC.to_s && options[:cert_store].is_a?(OpenSSL::X509::Store)
      end.returns(response(200, { items: [] }))

      assert_equal({ "items" => [] }, api.get("/apis/apps/v1/namespaces/production/deployments", "limit" => 1))
    end

    test "a list follows continue tokens and says when it stopped short" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      Http.stubs(:request).returns(response(200, { items: [ { a: 1 } ], metadata: { continue: "next" } }))
                          .then.returns(response(200, { items: [ { a: 2 } ], metadata: {} }))

      listing = api.list("/api/v1/namespaces/production/pods")
      assert_equal [ 1, 2 ], listing.items.map { |item| item["a"] }
      assert_not listing.incomplete?

      Http.stubs(:request).returns(response(200, { items: [ { a: 1 } ], metadata: { continue: "more" } }))
      assert api.list("/api/v1/namespaces/production/pods").incomplete?
    end

    test "the API server's refusals are raised by kind with its own message, and a certificate failure says why" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      Http.stubs(:request).returns(response(403, { kind: "Status", message: "deployments.apps is forbidden" }))
      assert_equal "The API server answered 403: deployments.apps is forbidden", assert_raises(KubernetesApi::Forbidden) { api.get("/x") }.message

      Http.stubs(:request).returns(response(404, { message: "not found" }))
      assert_raises(KubernetesApi::NotFound) { api.get("/x") }
      Http.stubs(:request).returns(response(401, { message: "Unauthorized" }))
      assert_equal "The API server answered 401: Unauthorized. The cluster did not accept the token. It may have expired.",
                   assert_raises(KubernetesApi::Error) { api.get("/x") }.message
      Http.stubs(:request).returns(response(429, {}))
      assert_kind_of Integrations::RateLimited, assert_raises(KubernetesApi::Error) { api.get("/x") }

      Http.stubs(:request).raises(KubernetesApi::Error, "could not reach cluster.example.com (OpenSSL::SSL::SSLError)")
      assert_match "not signed by the CA certificate given", assert_raises(KubernetesApi::Error) { api.get("/x") }.message
    end

    test "a watch asks from a version with bookmarks for a bounded time, and hands over each event however the stream is cut" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      lines = [ { type: "MODIFIED", object: { metadata: { name: "web", resourceVersion: "12" } } },
                { type: "BOOKMARK", object: { metadata: { resourceVersion: "15" } } } ].map { |event| "#{event.to_json}\n" }.join
      Http.expects(:request).with do |uri, _request, **options|
        URI.decode_www_form(uri.query).to_h == { "watch" => "true", "resourceVersion" => "10", "allowWatchBookmarks" => "true", "timeoutSeconds" => "50" } &&
          options[:read_timeout] == 65
      end.yields(streamed(200, lines))

      seen = []
      api.watch("/apis/apps/v1/namespaces/production/deployments", resource_version: "10") { |event| seen << [ event["type"], event.dig("object", "metadata", "resourceVersion") ] }

      assert_equal [ [ "MODIFIED", "12" ], [ "BOOKMARK", "15" ] ], seen
    end

    test "a watch from a version the server no longer keeps raises Gone, said as an answer or as an event, and a refusal by kind" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      expired = { type: "ERROR", object: { kind: "Status", code: 410, message: "too old resource version: 10 (20)" } }.to_json

      Http.stubs(:request).yields(streamed(200, "#{expired}\n"))
      assert_equal "The API server answered 410: too old resource version: 10 (20)", assert_raises(KubernetesApi::Gone) { api.watch("/x", resource_version: "10") { nil } }.message
      Http.stubs(:request).yields(streamed(410, { kind: "Status", message: "Expired" }.to_json))
      assert_raises(KubernetesApi::Gone) { api.watch("/x", resource_version: "10") { nil } }
      Http.stubs(:request).yields(streamed(403, { kind: "Status", message: "deployments.apps is forbidden: cannot watch" }.to_json))
      assert_raises(KubernetesApi::Forbidden) { api.watch("/x", resource_version: "10") { nil } }
    end

    test "a log comes back as text, and a log the API server refuses raises like any other call" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      Http.stubs(:request).returns(stub(code: "200", body: "2026-10-04T11:58:00Z GET /checkout 500\n", :[] => nil))
      assert_equal "2026-10-04T11:58:00Z GET /checkout 500\n", api.text("/api/v1/namespaces/production/pods/web/log")

      Http.stubs(:request).returns(response(404, { kind: "Status", message: "pods \"web\" not found" }))
      assert_equal "The API server answered 404: pods \"web\" not found", assert_raises(KubernetesApi::NotFound) { api.text("/api/v1/namespaces/production/pods/web/log") }.message
    end

    test "a patch says its kind and sends its body as JSON" do
      api = KubernetesApi.new(server: "https://cluster.example.com", token: "sa-token", ca: @ca)
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/apis/apps/v1/namespaces/production/deployments/web/scale" && request.is_a?(Net::HTTP::Patch) &&
          request["Content-Type"] == KubernetesApi::PATCH_MERGE && JSON.parse(request.body) == { "spec" => { "replicas" => 3 } }
      end.returns(response(200, { spec: { replicas: 3 } }))

      api.patch("/apis/apps/v1/namespaces/production/deployments/web/scale", { "spec" => { "replicas" => 3 } }, KubernetesApi::PATCH_MERGE)
    end

    private

    # An answer read as a stream, in two chunks cut mid-line, or read whole for a refusal.
    def streamed(code, body)
      answer = Object.new
      answer.define_singleton_method(:code) { code.to_s }
      answer.define_singleton_method(:body) { body }
      answer.define_singleton_method(:read_body) { |&block| [ body[0, 25], body[25..] ].each { |chunk| block.call(chunk) } }
      answer
    end

    def response(code, body) = stub(code: code.to_s, body: body.to_json)

    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end
end
