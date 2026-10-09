require "test_helper"

class PrincipalSerializerTest < ActiveSupport::TestCase
  test "what each member holds by default is worked out without asking again for every member" do
    workspace = workspaces(:slack_workspace_one)
    2.times { |index| workspace.workspace_memberships.create!(user: User.create!(email: "member#{index}@example.com", name: "Member #{index}"), role: :member, joined_at: Time.current) }
    principals = Ability::Principal.all(workspace)
    members = principals.grep(WorkspaceMembership).reject(&:admin_access?)
    assert members.many?, "expected more than one member to prove it"

    seen = []
    counter = ->(_, _, _, _, payload) { seen << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { PrincipalSerializer.many(principals).as_json }

    assert_empty seen.grep(/FROM "ability_roles"/), "the read packs are looked up once, with the listing"
    assert_empty seen.grep(/FROM "workspaces"/)
  end
end
