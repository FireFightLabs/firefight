require "test_helper"

module Integrations
  class HttpTest < ActiveSupport::TestCase
    class AcmeError < Integrations::Error; end

    setup do
      @uri = URI.parse("https://api.acme.example/v1/things")
    end

    test "an answer is read as JSON, a 2xx that is not JSON still counts as done, and a refusal says the provider's own reason" do
      Http.stubs(:request).returns(response(200, '{"things":[1]}'))
      assert_equal({ "things" => [ 1 ] }, json)

      Http.stubs(:request).returns(response(204, ""))
      assert_equal({}, json)

      Http.stubs(:request).returns(response(403, '{"message":"Missing scope: read"}'))
      assert_equal "Acme answered 403: Missing scope: read", assert_raises(AcmeError) { json }.message

      Http.stubs(:request).returns(response(502, "<html>Bad gateway</html>"))
      assert_equal "Acme answered 502 with something that is not JSON", assert_raises(AcmeError) { json }.message
    end

    test "a 404 is marked not found whatever class the client raises it as, and nothing else is" do
      Http.stubs(:request).returns(response(404, '{"message":"Project not found"}'))
      error = assert_raises(AcmeError) { json }
      assert_kind_of Integrations::NotFound, error

      Http.stubs(:request).returns(response(500, '{"message":"Internal error"}'))
      assert_not_kind_of Integrations::NotFound, assert_raises(AcmeError) { json }
    end

    test "a provider's reason is read whether it is words, an object or a list" do
      {
        '{"error":"invalid_token"}' => "invalid_token",
        '{"error":{"message":"Missing scope"}}' => "Missing scope",
        '{"error":{"detail":"Token expired"}}' => "Token expired",
        '{"errors":[{"message":"Name taken"},{"detail":"Size too big"}]}' => "Name taken, Size too big",
        '{"errors":["first","second"]}' => "first, second",
        '{"errors":["Name taken.","Size too big."]}' => "Name taken, Size too big",
        '{"error_description":"Bad grant","error":"invalid_grant"}' => "Bad grant",
        '{"message":"Not found"}' => "Not found",
        '{"error":{"code":12},"detail":"Gone"}' => "Gone",
        '{"other":1}' => "no reason given"
      }.each do |body, said|
        Http.stubs(:request).returns(response(400, body))
        assert_equal "Acme answered 400: #{said}", assert_raises(AcmeError) { json }.message, body
      end
    end

    test "a caller that tells answers apart by their status is given it with the body" do
      Http.stubs(:request).returns(response(202, '{"state":"queued"}'))
      assert_equal Http::Answer.new(status: 202, body: { "state" => "queued" }), json(with_status: true)

      Http.stubs(:request).returns(response(201, ""))
      assert_equal [ 201, {} ], json(with_status: true).then { |answer| [ answer.status, answer.body ] }
    end

    test "an answer carries its headers when asked, and an endpoint that answers text is read as text" do
      Http.stubs(:request).returns(response(200, '[{"id":1}]', headers: { "X-Next-Page" => [ "3" ], "Content-Type" => [ "application/json" ] }))
      answer = json(with_status: true)
      assert_equal [ [ { "id" => 1 } ], "3", "3" ], [ answer.body, answer.header("x-next-page"), answer.header("X-Next-Page") ]

      Http.stubs(:request).returns(response(200, "line one\nfailed: tests"))
      assert_equal "line one\nfailed: tests", json(as: :text)
      assert_equal "line one\nfailed: tests", json(as: :text, with_status: true).body

      Http.stubs(:request).returns(response(404, '{"message":"404 Job Not Found"}'))
      assert_equal "Acme answered 404: 404 Job Not Found", assert_raises(AcmeError) { json(as: :text) }.message
    end

    test "a documented redirect to stored content is followed through download, without the provider's credentials" do
      redirected = response(302, "", headers: { "location" => [ "https://logs.acme.example/step/1?sig=x" ] })
      redirected.stubs(:[]).with("location").returns("https://logs.acme.example/step/1?sig=x")
      Http.stubs(:request).returns(redirected)
      Http.expects(:download).with("https://logs.acme.example/step/1?sig=x", provider_key: "acme", error_class: AcmeError, limit: 20).returns("build failed here")

      assert_equal "build failed here", json(redirect: :download, provider_key: "acme", download_limit: 20)
    end

    test "without being asked, a redirect is not followed and reads as an answer that is not JSON" do
      redirected = response(302, "")
      Http.stubs(:request).returns(redirected)
      Http.expects(:download).never

      assert_equal "Acme answered 302 with something that is not JSON", assert_raises(AcmeError) { json }.message
    end

    test "a 429 is the client's own error, marked rate limited, so either rescue catches it" do
      Http.stubs(:request).returns(response(429, '{"error":{"message":"slow down"}}'))

      error = assert_raises(AcmeError) { json }
      assert_kind_of Integrations::RateLimited, error
      assert_equal "Acme answered 429: slow down", error.message
    end

    test "a client reads its provider's reason its own way, and names a sharper error for some answers" do
      Http.stubs(:request).returns(response(401, '{"errors":[{"detail":"token expired"}]}'))
      expired = Class.new(AcmeError)

      error = assert_raises(expired) do
        json(reason: ->(body) { body.dig("errors", 0, "detail") }, refine: ->(code, said) { expired if code == 401 && said.include?("expired") })
      end
      assert_equal "Acme answered 401: token expired", error.message
    end

    test "a file at a signed address is fetched on a public address only, without credentials, and keeps its tail" do
      PublicAddress.expects(:check!).with("logs.acme.example", provider_key: "acme").returns(PublicAddress::Checked.new(ip: IPAddr.new("203.0.113.7"), private: false))
      Http.expects(:request).with { |uri, request, ipaddr:, **| uri.host == "logs.acme.example" && request["Authorization"].nil? && ipaddr == "203.0.113.7" }
          .returns(response(200, "line one\nline two\nfailed here"))

      assert_equal "failed here", Http.download("https://logs.acme.example/job/1?sig=x", provider_key: "acme", error_class: AcmeError, limit: 11)

      assert_equal "The file is at an address that is not https.",
                   assert_raises(AcmeError) { Http.download("http://logs.acme.example/job/1", provider_key: "acme", error_class: AcmeError, limit: 10) }.message
      PublicAddress.stubs(:check!).raises(PublicAddress::Refused, "logs.acme.example is on a private network, which Firefight does not connect to.")
      assert_match "private network", assert_raises(AcmeError) { Http.download("https://logs.acme.example/x", provider_key: "acme", error_class: AcmeError, limit: 10) }.message
    end

    test "a connection dropped or answered with something that is not HTTP is the client's own error, never the platform's" do
      [ EOFError, IOError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::BufError ].each do |raised|
        Net::HTTP.stubs(:start).raises(raised)

        error = assert_raises(Integrations::Error) { Integrations::Http.request(URI("https://api.example.com/x"), Net::HTTP::Get.new("/x"), error_class: Integrations::Error) }
        assert_equal "could not reach api.example.com (#{raised.name})", error.message
      end
    end

    test "a host that does not answer in time is marked timed out, and a dropped connection is not" do
      [ Net::ReadTimeout, Net::OpenTimeout ].each do |raised|
        Net::HTTP.stubs(:start).raises(raised)

        error = assert_raises(AcmeError) { Http.request(@uri, Net::HTTP::Get.new(@uri), error_class: AcmeError) }
        assert_kind_of Integrations::TimedOut, error
        assert_equal "could not reach api.acme.example (#{raised.name})", error.message
      end

      Net::HTTP.stubs(:start).raises(EOFError)
      assert_not_kind_of Integrations::TimedOut, assert_raises(AcmeError) { Http.request(@uri, Net::HTTP::Get.new(@uri), error_class: AcmeError) }
    end

    test "a path segment is escaped, so a name with a slash stays one segment" do
      assert_equal "a%2Fb%20c", Http.segment("a/b c")
    end

    private

    def json(**) = Http.json(@uri, Net::HTTP::Get.new(@uri), error_class: AcmeError, provider_name: "Acme", **)

    def response(code, body, headers: {})
      stub(code: code.to_s, body: body, to_hash: headers)
    end
  end
end
