require "test_helper"

class AlertAddressSecretTest < ActiveSupport::TestCase
  # The env the rest of the stack is handed.
  def passed_on(path, query: nil)
    uri = query ? "#{path}?#{query}" : path
    env = { "PATH_INFO" => path, "REQUEST_PATH" => path, "REQUEST_URI" => uri, "ORIGINAL_FULLPATH" => uri, "QUERY_STRING" => query.to_s }
    AlertAddressSecret.new(->(_inner) { [ 200, {}, [ "OK" ] ] }).call(env)
    env
  end

  test "takes the secret out of every copy of the path and keeps it in the env" do
    env = passed_on("/api/v1/alerts/abc123/s3cret", query: "x=1")

    assert_equal "s3cret", env[AlertAddressSecret::ENV_KEY]
    assert_equal "/api/v1/alerts/abc123", env["PATH_INFO"]
    assert_equal "/api/v1/alerts/abc123", env["REQUEST_PATH"]
    assert_equal "/api/v1/alerts/abc123?x=1", env["REQUEST_URI"]
    assert_equal "/api/v1/alerts/abc123?x=1", env["ORIGINAL_FULLPATH"]
    assert_equal [ AlertAddressSecret::ENV_KEY ], env.select { |_key, value| value.to_s.include?("s3cret") }.keys
  end

  test "leaves every other path as it is" do
    [ "/api/v1/alerts/abc123", "/api/v1/alerts/abc123/s3cret/more", "/api/v1/issue_events/token", "/app/settings" ].each do |path|
      env = passed_on(path)

      assert_equal path, env["PATH_INFO"]
      assert_nil env[AlertAddressSecret::ENV_KEY]
    end
  end
end
