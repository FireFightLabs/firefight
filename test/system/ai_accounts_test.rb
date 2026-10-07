require "application_system_test_case"

class AiAccountsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "an admin adds accounts, sees which ones work and why one does not, edits one without seeing its key, and deletes one" do
    FirefightAi.stubs(:check_account).with do |choice, **|
      raise FirefightAi::TerminalError.new("401 invalid api key", reason: "UnauthorizedError") if choice.provider == "openai"

      true
    end
    visit settings_workspace_path
    assert_text "AI accounts"
    assert_text "No accounts yet."
    show_card
    page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-empty.png"))

    click_button "Add account"
    within("[role=dialog]") do
      assert_text "Add an AI account"
      fill_in "Name", with: "Team Anthropic"
      fill_in "API key", with: "sk-ant-team-key-4f2a"
      choose_model "Main model", "claude-sonnet-4-5"
      choose_model "Quick model", "claude-haiku-4-5"
      page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-add.png"))
      click_button "Add and check"
    end
    assert_text "Team Anthropic was added and works."
    assert_no_selector "[role=dialog]"

    click_button "Add account"
    within("[role=dialog]") do
      find("button[role=combobox]", match: :first).click
    end
    find("[role=option]", text: "OpenAI").click
    within("[role=dialog]") do
      fill_in "API key", with: "sk-typo"
      choose_model "Main model", "gpt-4o"
      choose_model "Quick model", "gpt-4o-mini"
      click_button "Add and check"
    end
    assert_text "OpenAI was added, but the check failed. The provider refused the key. Halon will skip it until a check passes."
    assert_text "Key refused"
    assert_button "Check again"
    show_card
    page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-list.png"))

    row(@workspace.workspace_ai_accounts.find_by!(label: "Team Anthropic")).find("button", text: "Actions").click
    find("[role=menuitem]", text: "Edit").click
    within("[role=dialog]") do
      assert_text "API key ending in 4f2a. Enter a new one to replace it."
      assert_equal "", find_field("API key").value
      page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-edit.png"))
      click_button "Cancel"
    end

    row(@workspace.workspace_ai_accounts.find_by!(label: "OpenAI")).find("button[role=switch]").click
    assert_text "OpenAI was turned off. Halon will skip it."

    row(@workspace.workspace_ai_accounts.find_by!(label: "Team Anthropic")).find("button", text: "Actions").click
    find("[role=menuitem]", text: "Delete").click
    within("[role=dialog]") do
      assert_text "Delete Team Anthropic?"
      assert_text "Its key is deleted from Firefight for good. Halon will use the next account."
      page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-delete.png"))
      click_button "Delete"
    end
    assert_text "Team Anthropic was deleted."
    assert_equal [ "OpenAI" ], @workspace.workspace_ai_accounts.reload.map(&:label)

    page.current_window.resize_to(390, 1400)
    visit settings_workspace_path
    show_card
    page.save_screenshot(Rails.root.join("tmp/screenshots/ai-accounts-phone.png"))
    assert_equal page.evaluate_script("document.documentElement.clientWidth"), page.evaluate_script("document.documentElement.scrollWidth")
  end

  private

  def choose_model(label, model)
    find("label", text: label, exact_text: true).find(:xpath, "..").find("button[role=combobox]").click
    page.document.find("[cmdk-item]", text: model, exact_text: true).click
  end

  def show_card
    page.execute_script("arguments[0].scrollIntoView({ block: 'start' })", find("[data-slot=card-title]", text: "AI accounts"))
  end

  def row(account)
    find("tr", text: account.label)
  end
end
