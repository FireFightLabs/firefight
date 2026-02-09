module Interactions
  class HomeActionSelectHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      selected_value = payload.dig("actions", 0, "selected_option", "value")
      view = payload["view"]

      help_text = Slack::ModalBuilder.home_command_help(selected_value)

      updated_blocks = view["blocks"].map do |block|
        if block["block_id"] == "command_details_block"
          block.merge("text" => { "type" => "mrkdwn", "text" => help_text })
        else
          block
        end
      end

      Slack::Client.update_modal(
        workspace: workspace,
        view_id: view["id"],
        view: {
          type: "modal",
          callback_id: Slack::Identifiers::INCIDENT_HOME_MODAL,
          title: view["title"],
          close: view["close"],
          blocks: updated_blocks
        }
      )

      nil
    rescue => e
      Rails.logger.error({ event: "incident_home.update_error", error: e.message })
      nil
    end
  end
end
