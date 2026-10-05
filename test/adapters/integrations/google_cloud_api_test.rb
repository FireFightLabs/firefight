require "test_helper"

module Integrations
  class GoogleCloudApiTest < ActiveSupport::TestCase
    PRIVATE_KEY = OpenSSL::PKey::RSA.new(2048)
    KEY = { "type" => "service_account", "project_id" => "acme-prod", "private_key_id" => "key-1", "private_key" => PRIVATE_KEY.to_pem,
            "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "token_uri" => GoogleCloudApi::TOKEN_URI }.to_json

    setup do
      @workspace = workspaces(:slack_workspace_one)
      integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
      @row = integration.integration_environments.create!(credentials: { "service_account_key" => KEY }.to_json)
    end

    test "the key signs an assertion Google trades for a token, which is cached on the row and sent as a bearer" do
      Http.expects(:request).with do |uri, request, **|
        next false unless uri.to_s == GoogleCloudApi::TOKEN_URI

        form = URI.decode_www_form(request.body).to_h
        claims, header = JWT.decode(form["assertion"], PRIVATE_KEY.public_key, true, algorithm: "RS256")
        form["grant_type"] == GoogleCloudApi::GRANT_TYPE && claims["iss"] == "firefight@acme-prod.iam.gserviceaccount.com" &&
          claims["aud"] == GoogleCloudApi::TOKEN_URI && claims["scope"] == GoogleCloudApi::SCOPE && claims["exp"] - claims["iat"] == 3600 &&
          header["kid"] == "key-1"
      end.returns(response(200, { access_token: "ya29.token", expires_in: 3599, token_type: "Bearer" }))
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://cloudresourcemanager.googleapis.com/v1/projects/acme-prod" && request["Authorization"] == "Bearer ya29.token"
      end.twice.returns(response(200, { projectId: "acme-prod" }))

      assert_equal "acme-prod", GoogleCloudApi.new(KEY, token_cache: ConnectionSettings.of(@row)).project("acme-prod")["projectId"]
      assert_equal "ya29.token", @row.reload.credentials_hash.dig(GoogleCloudApi::TOKEN_CACHE_KEY, "token")
      GoogleCloudApi.new(KEY, token_cache: ConnectionSettings.of(@row)).project("acme-prod")
    end

    test "a key Google refuses says its reason, and a 429 from the token endpoint is a rate limit" do
      Http.stubs(:request).returns(response(400, { error: "invalid_grant", error_description: "Invalid JWT Signature." }))
      assert_equal "Google answered 400: Invalid JWT Signature.", assert_raises(GoogleCloudApi::Error) { GoogleCloudApi.new(KEY).project("acme-prod") }.message

      Http.stubs(:request).returns(response(429, { error: "rate_limit_exceeded" }))
      assert_raises(Integrations::RateLimited) { GoogleCloudApi.new(KEY).project("acme-prod") }
    end

    test "a key that is not a service account key is refused with what to paste" do
      assert_match "not JSON", assert_raises(GoogleCloudApi::Error) { GoogleCloudApi.new("ya29") }.message
      assert_match "not a service account key", assert_raises(GoogleCloudApi::Error) { GoogleCloudApi.new({ "type" => "authorized_user" }.to_json) }.message
    end

    test "Google's refusal is raised with its own reason, and a 429 and a 403 are told apart" do
      GoogleCloudApi.any_instance.stubs(:access_token).returns("ya29.token")
      api = GoogleCloudApi.new(KEY)

      Http.stubs(:request).returns(response(403, { error: { message: "Cloud SQL Admin API has not been used in project acme-prod" } }))
      assert_equal "Google Cloud answered 403: Cloud SQL Admin API has not been used in project acme-prod",
                   assert_raises(GoogleCloudApi::Forbidden) { api.sql_instances("acme-prod") }.message
      Http.stubs(:request).returns(response(429, { error: { message: "Quota exceeded" } }))
      assert_raises(Integrations::RateLimited) { api.clusters("acme-prod") }
    end

    test "log entries are searched newest first across pages, and an empty page with a token is followed" do
      GoogleCloudApi.any_instance.stubs(:access_token).returns("ya29.token")
      bodies = []
      Http.stubs(:request).with { |_uri, request, **| bodies << JSON.parse(request.body) }
          .returns(response(200, { entries: [], nextPageToken: "more" }), response(200, { entries: [ { textPayload: "boom" } ] }))

      entries = GoogleCloudApi.new(KEY).log_entries("acme-prod", "severity>=ERROR", limit: 50)

      assert_equal [ "boom" ], entries.map { |entry| entry["textPayload"] }
      assert_equal [ "projects/acme-prod" ], bodies.first["resourceNames"]
      assert_equal "timestamp desc", bodies.first["orderBy"]
      assert_equal "more", bodies.last["pageToken"]
    end

    test "every zone's instances are read from the aggregated list" do
      GoogleCloudApi.any_instance.stubs(:access_token).returns("ya29.token")
      Http.stubs(:request).returns(response(200, { items: { "zones/us-central1-a" => { instances: [ { name: "vm-1" } ] },
                                                            "zones/europe-west1-b" => { warning: { code: "NO_RESULTS_ON_PAGE" } } } }))

      assert_equal [ "vm-1" ], GoogleCloudApi.new(KEY).compute_instances("acme-prod").items.map { |instance| instance["name"] }
    end

    private

    def response(code, body) = stub(code: code.to_s, body: body.to_json)
  end
end
