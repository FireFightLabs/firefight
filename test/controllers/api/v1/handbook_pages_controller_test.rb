require "test_helper"

class Api::V1::HandbookPagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    _, @token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Personal")
    @releases = handbook_page!(@workspace, "How we release", "Tag main.", by: @admin)
  end

  test "lists the pages without their text, and shows one whole" do
    get api_v1_handbook_pages_url, headers: api_headers(token: @token)
    assert_response :success
    listed = json_response["pages"].sole
    assert_equal [ "How we release", "written" ], listed.values_at("title", "kind")
    assert_not listed.key?("text")

    get api_v1_handbook_page_url(@releases), headers: api_headers(token: @token)
    assert_equal [ "Tag main.", @releases.current_wording.id ], json_response["page"].values_at("text", "wording_id")
  end

  test "a page sets freeze windows, an update without them keeps them, and one that does not hold is refused" do
    window = { name: "End of year", repeat: "once", time_zone: "Europe/Berlin", starts_at: "2026-12-23T18:00", ends_at: "2027-01-04T09:00" }
    post api_v1_handbook_pages_url, params: { title: "Freeze windows", freeze_windows: [ window ] }.to_json, headers: api_headers(token: @token)
    assert_response :created
    assert_equal [ window.stringify_keys ], json_response.dig("page", "freeze_windows")
    page = Chat::HandbookPage.find(json_response.dig("page", "id"))

    patch api_v1_handbook_page_url(page), params: { text: "Hotfixes still go out." }.to_json, headers: api_headers(token: @token)
    assert_equal [ "End of year" ], page.reload.freeze_rules.map(&:name)

    patch api_v1_handbook_page_url(page), params: { freeze_windows: [ window.merge(ends_at: "2026-12-01T09:00") ] }.to_json, headers: api_headers(token: @token)
    assert_response :unprocessable_entity
    assert_match "End of year needs to end after it starts.", response.body
  end

  test "creates a page, updates it keeping history, refuses an edit over someone else's, and deletes it" do
    post api_v1_handbook_pages_url, params: { title: "Who owns what", text: "Payments owns checkout." }.to_json, headers: api_headers(token: @token)
    assert_response :created
    page = Chat::HandbookPage.find(json_response.dig("page", "id"))
    seen = page.current_wording.id

    patch api_v1_handbook_page_url(page), params: { text: "Payments owns checkout and billing.", wording_id: seen }.to_json, headers: api_headers(token: @token)
    assert_response :success
    assert_equal 2, page.wordings.count

    patch api_v1_handbook_page_url(page), params: { text: "Over it", wording_id: seen }.to_json, headers: api_headers(token: @token)
    assert_response :conflict

    delete api_v1_handbook_page_url(page), headers: api_headers(token: @token)
    assert_response :no_content
    assert_not Chat::HandbookPage.exists?(page.id)
  end

  test "a page saying who directs Halon names a role by its slug" do
    post api_v1_handbook_pages_url, params: { title: Chat::HandbookPage::DIRECTING_TITLE, incident_role: "communications_lead" }.to_json,
                                    headers: api_headers(token: @token)

    assert_response :created
    assert_equal "communications_lead", json_response.dig("page", "incident_role")
  end

  test "a synced page is refused, and a key without the permission is forbidden" do
    source = Chat::HandbookSource.create!(workspace: @workspace, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/")
    synced = Chat::HandbookPage.create_written!(@workspace, title: "Deploys", text: "Run make deploy", by: nil, kind: Chat::HandbookPage::KIND_SYNCED,
                                                            source: source, source_path: "docs/deploys.md")
    patch api_v1_handbook_page_url(synced), params: { text: "Changed" }.to_json, headers: api_headers(token: @token)
    assert_response :unprocessable_entity
    assert_equal "page_synced", json_response.dig("error", "type")

    _, read_only = create_service_key(workspace: @workspace, created_by: @admin, permissions: { "handbook" => [ "read" ] })
    delete api_v1_handbook_page_url(@releases), headers: api_headers(token: read_only)
    assert_response :forbidden
  end
end
