require "test_helper"

class Slack::InteractionParserTest < ActiveSupport::TestCase
  test "a block action carries its response_url as the prompt handle" do
    interaction = Slack::InteractionParser.parse(
      "type" => Interaction::BLOCK_ACTIONS,
      "team" => { "id" => "T12345678" },
      "user" => { "id" => "U12345678" },
      "trigger_id" => "12345.trigger",
      "response_url" => "https://hooks.slack.com/actions/T12345678/456/abc",
      "actions" => [ { "action_id" => Identifiers::CREATE_ACTION_FROM_REACTION, "value" => "{}" } ]
    )

    assert_equal Interaction::BLOCK_ACTIONS, interaction.type
    assert_equal Identifiers::CREATE_ACTION_FROM_REACTION, interaction.action_id
    assert_equal "https://hooks.slack.com/actions/T12345678/456/abc", interaction.prompt_handle
  end

  test "a view submission has no prompt handle" do
    interaction = Slack::InteractionParser.parse(
      "type" => Interaction::VIEW_SUBMISSION,
      "team" => { "id" => "T12345678" },
      "user" => { "id" => "U12345678" },
      "view" => { "callback_id" => Identifiers::CREATE_ACTION_MODAL, "private_metadata" => ModalState.encode(incident_id: 1) }
    )

    assert_nil interaction.prompt_handle
    assert_equal 1, interaction.metadata.incident_id
  end
end
