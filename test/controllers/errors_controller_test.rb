require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "an unmatched path renders the branded page instead of raising" do
    get "/app/settings/does-not-exist", headers: inertia_headers

    assert_response :not_found
    assert_equal "errors/not-found", JSON.parse(response.body)["component"]
  end

  test "an unmatched path under a nested route is caught too" do
    get "/totally/made/up/path", headers: inertia_headers

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
    get "/500", headers: inertia_headers
    assert_response :internal_server_error
    assert_equal "errors/server-error", JSON.parse(response.body)["component"]

    get "/422", headers: inertia_headers
    assert_response :unprocessable_content
    assert_equal "errors/unprocessable", JSON.parse(response.body)["component"]
  end

  test "real routes still resolve ahead of the catch-all" do
    get "/login", headers: inertia_headers
    assert_response :success

    get "/up"
    assert_response :success
  end

  test "Active Storage routes are not swallowed by the catch-all" do
    routes = Rails.application.routes

    blob = routes.recognize_path("/rails/active_storage/blobs/redirect/abc/photo.png", method: :get)
    assert_equal "active_storage/blobs/redirect", blob[:controller]

    upload = routes.recognize_path("/rails/active_storage/direct_uploads", method: :post)
    assert_equal "active_storage/direct_uploads", upload[:controller]

    unmatched = routes.recognize_path("/nope", method: :get)
    assert_equal "errors", unmatched[:controller]
  end
end
