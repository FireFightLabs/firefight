require "test_helper"

module Integrations
  class GitHttpTest < ActiveSupport::TestCase
    test "a request goes to the repository's git address signed with the connection's credential, its body streamed, and the answer streams back" do
      remote = CodeReading::Remote.new(root: "https://github.com", user: "x-access-token", token: -> { "ghs_installation" })
      body = StringIO.new("0000PACK")
      sent = nil
      answer = Net::HTTPOK.new("1.1", "200", "OK")
      answer["Content-Type"] = "application/x-git-receive-pack-result"
      answer["Set-Cookie"] = "never passed"
      answer.stubs(:read_body).multiple_yields([ "000e" ], [ "unpack ok\n" ])
      Http.expects(:request).with { |uri, request, **| (sent = [ uri.to_s, request ]) }.yields(answer)

      heard = []
      GitHttp.forward(remote, "acme/api", "git-receive-pack", method: :post, body: body, length: 8,
                                                              headers: { "Content-Type" => "application/x-git-receive-pack-request", "Cookie" => "x" }) { |*event| heard << event }

      uri, request = sent
      assert_equal "https://github.com/acme/api.git/git-receive-pack", uri
      assert_equal "Basic #{Base64.strict_encode64('x-access-token:ghs_installation')}", request["Authorization"]
      assert_equal [ body, 8, "application/x-git-receive-pack-request", nil ], [ request.body_stream, request.content_length, request["Content-Type"], request["Cookie"] ]
      assert_equal [ [ :start, 200, { "content-type" => "application/x-git-receive-pack-result" } ], [ :chunk, "000e" ], [ :chunk, "unpack ok\n" ] ], heard
    end

    test "a body sent without a length goes on chunked" do
      remote = CodeReading::Remote.new(root: "https://github.com", user: "x-access-token", token: -> { "t" })
      sent = nil
      Http.expects(:request).with { |_uri, request, **| (sent = request) }

      GitHttp.forward(remote, "acme/api", "git-upload-pack", method: :post, body: StringIO.new("0000"), length: nil, headers: {}) { nil }

      assert_equal "chunked", sent["Transfer-Encoding"]
    end
  end
end
