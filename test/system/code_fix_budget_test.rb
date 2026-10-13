require "application_system_test_case"

# An admin sets what one code fix may spend on the Workspace settings page, beside who writes code fixes.
class CodeFixBudgetTest < ApplicationSystemTestCase
  PHONE = [ 390, 844 ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "an admin sets the code fix budget in dollars and cents, is told the new budget, and a budget out of range says the range" do
    visit settings_workspace_path

    assert_field "Spend at most", with: "2"
    assert_text "$2 by default, and anything from $0.50 to $50."
    budget = find_field("Spend at most")
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", budget)
    shot("code-fix-budget")

    budget.fill_in(with: "75")
    click_button "Save changes"
    assert_text "A code fix's budget must be between $0.50 and $50."
    assert_equal 200, @workspace.reload.code_fix_budget_cents
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", find_field("Spend at most"))
    shot("code-fix-budget-refused")

    find_field("Spend at most").fill_in(with: "5.50")
    click_button "Save changes"
    assert_toast "Code fix budget was set to $5.50."
    assert_no_text "A code fix's budget must be between $0.50 and $50."
    assert_equal 550, @workspace.reload.code_fix_budget_cents

    page.current_window.resize_to(*PHONE)
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", find_field("Spend at most"))
    shot("code-fix-budget-phone")
  end

  private

  def shot(name) = page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
end
