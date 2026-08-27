require "test_helper"

class InteractionTest < ActiveSupport::TestCase
  test "metadata is parsed once and blank means a modal that carries nothing" do
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, private_metadata: nil)

    assert_same ModalState::EMPTY, interaction.metadata
    assert_nil interaction.incident_id
  end

  test "metadata exposes what the modal encoded" do
    encoded = ModalState.encode(incident_id: "inc-1", temp_message_ts: "1.2", channel_id: "C1")
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, private_metadata: encoded)

    assert_equal "inc-1", interaction.incident_id
    assert_equal "1.2", interaction.metadata.temp_message_ts
    assert_equal "C1", interaction.metadata.channel_id
  end

  test "a bare incident id from a modal opened before the cutover still resolves" do
    id = SecureRandom.uuid
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, private_metadata: id)

    assert_equal id, interaction.incident_id
  end

  test "malformed metadata is logged and treated as empty rather than raised at a handler" do
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, callback_id: "x", private_metadata: "{not json")

    assert_same ModalState::EMPTY, interaction.metadata
    assert_nil interaction.incident_id
  end
end
