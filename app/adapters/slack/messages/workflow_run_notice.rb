module Slack
  module Messages
    # What a workflow run says when it ends on its own: that it failed, with why and Halon's suggested fix when it made
    # one, or a one line all clear for a workflow that asked for one.
    module WorkflowRunNotice
      def self.failed(run, suggestion: false)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":x:  *#{Mrkdwn.escape(failed_title(run))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(run.error.presence || "It did not say why.").truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Halon suggested a fix, which waits on the run's page for someone to accept." } ] } if suggestion
        url = DashboardUrl.workflow_run(run)
        blocks << { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the run" }, url: url } ] } if url
        blocks
      end

      def self.failed_fallback(run) = "#{failed_title(run)}. #{run.error}".truncate(300)

      def self.failed_title(run) = "#{run.workflow.name} failed"

      def self.all_clear(run)
        url = DashboardUrl.workflow_run(run)
        said = "#{all_clear_fallback(run)}#{" <#{url}|Open the run>" if url}"
        [ { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  #{said}" } } ]
      end

      def self.all_clear_fallback(run) = "#{Mrkdwn.escape(run.workflow.name)} ran and found nothing to raise."
    end
  end
end
