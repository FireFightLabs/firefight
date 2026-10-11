require "test_helper"

# Model calls keep their connections to a provider open between calls, and a process running on fibers can name its own
# adapter, from the environment.
class FirefightAi::HttpAdapterTest < ActiveSupport::TestCase
  test "model calls go through net_http_persistent unless a process names another" do
    assert_equal :net_http_persistent, FirefightAi::Configuration.new.http_adapter
    assert_equal :net_http_persistent, RubyLLM.config.faraday_adapter
    assert_equal :net_http_persistent, RubyLLM.context { |_config| nil }.config.faraday_adapter, "a workspace's own account calls the same way"
  end

  test "the setting takes each adapter by name, a blank one keeps the default, and anything else is refused at boot" do
    configuration = FirefightAi::Configuration.new
    configuration.http_adapter = "async_http"
    assert_equal :async_http, configuration.http_adapter
    configuration.http_adapter = ""
    assert_equal :net_http_persistent, configuration.http_adapter
    assert_raises(ArgumentError) { configuration.http_adapter = "typhoeus" }
  end

  test "an adapter whose library is not installed is refused by name, saying which gem to add" do
    assert_equal :net_http_persistent, FirefightAi::HttpAdapter.load!(:net_http_persistent)
    FirefightAi::HttpAdapter.stubs(:require).with("async/http/faraday").raises(LoadError, "cannot load such file -- async/http/faraday")

    error = assert_raises(LoadError) { FirefightAi::HttpAdapter.load!(:async_http) }
    assert_match "FIREFIGHT_AI_HTTP_ADAPTER is async_http", error.message
  end
end
