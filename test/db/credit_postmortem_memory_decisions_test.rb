require "test_helper"
require Rails.root.join("db/migrate/20261006090200_credit_postmortem_memory_decisions")

class CreditPostmortemMemoryDecisionsTest < ActiveSupport::TestCase
  test "a postmortem's past decisions move from the draft's author to whoever completed it, and remember the postmortem" do
    workspace = workspaces(:slack_workspace_one)
    incident = incidents(:active_critical_ws1)
    author = workspace_memberships(:alice_workspace_one)
    completer = workspace_memberships(:bob_workspace_one)
    postmortem = Postmortem.create!(incident: incident, generated_by: author, title: "Pool", status: Postmortem::STATUS_IN_REVIEW, content: { "html" => "<p>Pool</p>" })
    postmortem.update_status!(Postmortem::STATUS_COMPLETED, by: completer)
    agreed = Chat::Memory.create!(workspace: workspace, text: "Sessions live in Redis", source: incident, state: Chat::Memory::STATE_CONFIRMED,
                                  confirmed_by: author, state_reason: CreditPostmortemMemoryDecisions::AGREES)
    replacement = Chat::Memory.create!(workspace: workspace, text: "The cause was the pool", source: incident, state: Chat::Memory::STATE_CONFIRMED,
                                       confirmed_by: author, added_by: author)
    contradicted = Chat::Memory.create!(workspace: workspace, text: "The cause was DNS", source: incident, state: Chat::Memory::STATE_REJECTED,
                                        rejected_by: author, state_reason: CreditPostmortemMemoryDecisions::SAYS_OTHERWISE, replaced_by: replacement)
    person = Chat::Memory.create!(workspace: workspace, text: "Checkout runs in Frankfurt", source: incident, state: Chat::Memory::STATE_CONFIRMED, confirmed_by: author)

    ActiveRecord::Migration.suppress_messages { CreditPostmortemMemoryDecisions.new.migrate(:up) }

    assert_equal [ completer, postmortem ], agreed.reload.values_at(:confirmed_by, :decided_by_postmortem)
    assert_equal [ completer, postmortem ], contradicted.reload.values_at(:rejected_by, :decided_by_postmortem)
    assert_equal [ completer, postmortem ], replacement.reload.values_at(:confirmed_by, :decided_by_postmortem)
    assert_equal [ author, nil ], person.reload.values_at(:confirmed_by, :decided_by_postmortem), "a person's own decision is untouched"
  end
end
