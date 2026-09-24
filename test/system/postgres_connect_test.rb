require "application_system_test_case"

class PostgresConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "a database is connected from a URL, and one Firefight will not reach is refused on the form" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "postgresql")

    within("[role=dialog]") do
      assert_text "Paste a connection URL for each environment."
      fill_in "Connection URL", with: "postgresql://reader:secret@10.1.2.3:5432/orders"
      click_button "Connect"
      assert_text "10.1.2.3 is on a private network, which Firefight does not connect to."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/postgres-connect.png"))
    assert_equal 0, workspaces(:slack_workspace_one).integrations.where(provider: "postgresql").count
  end
end
