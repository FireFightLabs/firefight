require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "an unmatched path renders the branded page instead of raising" do
    get "/app/settings/does-not-exist"

    assert_response :not_found
    assert_match "errors/not-found", response.body
  end

  test "an unmatched path under a nested route is caught too" do
    get "/totally/made/up/path"

    assert_response :not_found
  end

  test "a JSON client gets JSON rather than a page" do
    get "/api/v1/does-not-exist", headers: { "Accept" => "application/json" }

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]
  end

  test "a non-page request gets the status without a body" do
    get "/missing.png"

    assert_response :not_found
    assert_empty response.body
  end

  test "the exceptions_app targets render" do
    get "/500"
    assert_response :internal_server_error

    get "/422"
    assert_response :unprocessable_content
  end

  test "real routes still resolve ahead of the catch-all" do
    get "/login"
    assert_response :success

    get "/up"
    assert_response :success
  end
end
