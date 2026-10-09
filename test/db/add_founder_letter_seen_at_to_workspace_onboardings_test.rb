require "test_helper"
require Rails.root.join("db/migrate/20261009140000_add_founder_letter_seen_at_to_workspace_onboardings")

class AddFounderLetterSeenAtToWorkspaceOnboardingsTest < ActiveSupport::TestCase
  teardown { WorkspaceOnboarding.reset_column_information }

  test "a workspace past the founder letter is kept as having seen it, and one with no progress still shows it" do
    completed = sign_up("Completed Co").tap { |onboarding| onboarding.update!(completed_at: 1.day.ago) }
    checklist_done = sign_up("Checklist Co").tap { |onboarding| onboarding.update!(checklist_completed_at: 1.day.ago) }
    ai_chosen = sign_up("Chosen Co").tap do |onboarding|
      onboarding.update!(ai_choice: WorkspaceOnboarding::AI_ACCOUNT, ai_chosen_at: 1.day.ago)
    end
    stack_answered = sign_up("Stack Co").tap do |onboarding|
      onboarding.update!(stack_answers: { "observability" => WorkspaceOnboarding::ANSWER_UNUSED })
    end
    permissions = sign_up("Permissions Co").tap { |onboarding| onboarding.update!(permissions_reviewed_at: 1.day.ago) }
    untouched = sign_up("Untouched Co")

    migrate(:down)
    assert_not column_exists?
    migrate(:up)

    [ completed, checklist_done, ai_chosen, stack_answered, permissions ].each do |onboarding|
      assert onboarding.reload.founder_letter_seen_at, "#{onboarding.workspace.name} is past the letter"
    end
    assert_nil untouched.reload.founder_letter_seen_at
    assert untouched.founder_letter_pending?
  end

  test "rolling back removes the column" do
    migrate(:down)

    assert_not column_exists?
  end

  private

  def sign_up(name)
    owner = User.create!(email: "#{name.parameterize}@example.com", name: "Owner of #{name}")
    Workspace.sign_up!(name: name, user: owner).workspace.onboarding
  end

  def column_exists?
    ActiveRecord::Base.connection.column_exists?(:workspace_onboardings, :founder_letter_seen_at)
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddFounderLetterSeenAtToWorkspaceOnboardings.new.migrate(direction) }
    WorkspaceOnboarding.reset_column_information
  end
end
