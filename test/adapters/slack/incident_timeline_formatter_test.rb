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

  test "a fix step names the step and links what it produced where the words name it" do
    event = incidents(:active_critical_ws1).incident_events.create!(
      event_type: IncidentEvent::FIX_STEP_DONE,
      metadata: { position: 1, step_title: "Open a pull request with the change", result: "Opened a pull request: PR #856",
                  link_label: "PR #856", link_url: "https://github.com/FireFightLabs/firefight/pull/856" }
    )

    text = Slack::IncidentTimelineFormatter.to_block(event)[:section][:text][:text]

    assert_includes text, "*Fix step done*"
    assert_includes text, "Open a pull request with the change\nOpened a pull request: <https://github.com/FireFightLabs/firefight/pull/856|PR #856>"
  end
end
