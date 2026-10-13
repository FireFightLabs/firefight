require "test_helper"

class Slack::IncidentTimelineFormatterTest < ActiveSupport::TestCase
  test "a shared file's name is escaped like every posted text, so it can never notify or link" do
    event = incidents(:active_critical_ws1).incident_events.create!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: { file_name: "<!here> logs & <https://evil.example|ok>.txt", permalink: "https://acme.slack.com/files/F1" }
    )

    text = Slack::IncidentTimelineFormatter.to_block(event)[:section][:text][:text]

    assert_includes text, "&lt;!here&gt; logs &amp; &lt;https://evil.example|ok&gt;.txt · <https://acme.slack.com/files/F1|Open in Slack>"
    assert_not_includes text, "<!here>"
  end
end
