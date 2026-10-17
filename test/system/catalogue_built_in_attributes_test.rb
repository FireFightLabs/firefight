require "application_system_test_case"

class CatalogueBuiltInAttributesTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "a built-in type's attributes cannot be removed, and the button says why, while a custom type's can" do
    visit catalogue_type_path("team")
    click_on "Edit Type"

    within("[role='dialog']") do
      row = find("input[value='Description']").ancestor("div.rounded-md")
      remove = row.find("button:has(svg.tabler-icon-trash)")
      assert remove.disabled?
      remove.find(:xpath, "..").hover
    end
    assert_selector "[role='tooltip']", text: "Team is a built-in type, so its attributes cannot be removed."
    page.save_screenshot(Rails.root.join("tmp/screenshots/catalogue-built-in-attribute.png"))
    find("[role='dialog'] button", text: "Cancel").click

    visit catalogue_type_path("vendor")
    click_on "Edit Type"
    within("[role='dialog']") do
      assert_no_selector "button:has(svg.tabler-icon-trash)[disabled]"
      find("input[value='Tier']").ancestor("div.rounded-md").find("button:has(svg.tabler-icon-trash)").click
      assert_no_selector "input[value='Tier']"
    end
  end
end
