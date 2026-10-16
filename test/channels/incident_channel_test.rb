require "test_helper"

class IncidentChannelTest < ActionCable::Channel::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "a member of the incident's workspace who may read incidents follows its page" do
    stub_connection(current_user: users(:bob))

    subscribe(id: @incident.id)

    assert subscription.confirmed?
    assert_has_stream IncidentChannel.stream_name(@incident.id)
  end

  test "someone outside the incident's workspace is refused" do
    stub_connection(current_user: users(:bob))

    subscribe(id: incidents(:active_p0_ws2).id)

    assert subscription.rejected?
  end

  test "a member who may not read incidents is refused, by the same rule the page uses" do
    stub_connection(current_user: users(:bob))
    AbilityGateway.stubs(:permitted?).returns(false)

    subscribe(id: @incident.id)

    assert subscription.rejected?
  end

  test "an id that is not an incident is refused" do
    stub_connection(current_user: users(:bob))

    subscribe(id: SecureRandom.uuid)

    assert subscription.rejected?
  end
end
