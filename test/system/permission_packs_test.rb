require "application_system_test_case"

class PermissionPacksTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    northflank.tools.create!(name: "search_logs", read_only: true, enabled: true)
    @restart = northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @changes = northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
    sign_in(users(:alice), @workspace)
  end

  test "an admin gives a person a connection's changes pack from the quick grant panel, with a toast" do
    visit gateway_permissions_path

    assert_text "Who can do what"
    assert_text "Everyone reads every connected tool. Changes need a pack."
    click_button "Pick a person"
    find("[role=option]", text: "Bob Jones").click
    click_button "Pick a pack"
    assert_text "Every tool on Faylee (Northflank) that changes something."
    find("[role=option]", text: "Faylee (Northflank): changes").click
    page.save_screenshot(Rails.root.join("tmp/screenshots/permission-packs-quick-grant.png"))
    click_button "Give pack"

    assert_text "Bob Jones was granted Faylee (Northflank): changes."
    assert @bob.permitted_to?(@restart.ability_action, @workspace)
  end

  test "built-in packs are listed in their own group, read only, and a member's reads of a connection can be taken away" do
    visit gateway_permissions_path

    assert_text "Built-in packs"
    click_button "Faylee (Northflank): read"
    assert_text "Faylee (Northflank): read is kept in step with Faylee (Northflank)'s tools, so it cannot be changed by hand."
    assert_text "faylee.search_logs"
    assert_no_text "faylee.restart_service"
    assert find_button("Delete set", disabled: true)
    page.save_screenshot(Rails.root.join("tmp/screenshots/permission-packs-group.png"))

    click_button "Bob Jones"
    within(:xpath, "//div[./span/span/span[text()='Faylee (Northflank): read']]") { click_button "No access" }
    assert_text "Bob Jones can no longer read Faylee (Northflank)'s tools. Restore it to give it back."
    page.save_screenshot(Rails.root.join("tmp/screenshots/permission-packs-no-access.png"))
  end
end
