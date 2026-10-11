require "test_helper"

class PathSecretTest < ActiveSupport::TestCase
  # The env the rest of the stack is handed.
  def passed_on(path, query: nil)
    uri = query ? "#{path}?#{query}" : path
    env = { "PATH_INFO" => path, "REQUEST_PATH" => path, "REQUEST_URI" => uri, "ORIGINAL_FULLPATH" => uri, "QUERY_STRING" => query.to_s }
    PathSecret.new(->(_inner) { [ 200, {}, [ "OK" ] ] }).call(env)
    env
  end

  test "masks the secret in every copy of the path and keeps it in the env" do
    {
      "/api/v1/alerts/abc123/s3cret" => "/api/v1/alerts/abc123/[FILTERED]",
      "/api/v1/issue_events/s3cret" => "/api/v1/issue_events/[FILTERED]",
      "/api/v1/map_events/s3cret" => "/api/v1/map_events/[FILTERED]"
    }.each do |path, masked|
      env = passed_on(path, query: "x=1")

      assert_equal "s3cret", env[PathSecret::ENV_KEY]
      assert_equal masked, env["PATH_INFO"]
      assert_equal masked, env["REQUEST_PATH"]
      assert_equal "#{masked}?x=1", env["REQUEST_URI"]
      assert_equal "#{masked}?x=1", env["ORIGINAL_FULLPATH"]
      assert_equal [ PathSecret::ENV_KEY ], env.select { |_key, value| value.to_s.include?("s3cret") }.keys
    end
  end

  test "leaves every other path as it is" do
    [ "/api/v1/alerts/abc123", "/api/v1/alerts/abc123/s3cret/more", "/api/v1/app_events/github", "/app/settings" ].each do |path|
      env = passed_on(path)

      assert_equal path, env["PATH_INFO"]
      assert_nil env[PathSecret::ENV_KEY]
    end
  end
end
