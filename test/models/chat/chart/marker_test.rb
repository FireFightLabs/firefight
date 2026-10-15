require "test_helper"

class Chat::Chart::MarkerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    @started = Time.utc(2026, 9, 25, 14, 0)
  end

  test "a chart's marker names it by a short handle from its id" do
    chart = record("Memory of web").sole

    assert_equal chart.id.first(8), chart.handle
    assert_equal "{{chart:#{chart.handle}}}", Chat::Chart::Marker.for(chart)
  end

  test "the handles an answer names are read in order, once each, whatever the case or spacing" do
    text = "Web grew.\n\n{{chart:3F9A1C2E}}\n{{ chart: 9b2c4d1a }}\n\nAgain `{{chart:3f9a1c2e}}`."

    assert_equal %w[3f9a1c2e 9b2c4d1a], Chat::Chart::Marker.handles_in(text)
  end

  test "plain text drops a marker standing on its own line, with the line" do
    text = "Memory of web climbed at 14:00.\n\n{{chart:3f9a1c2e}}\n{{chart:9b2c4d1a}}\n\nThe job held steady."

    assert_equal "Memory of web climbed at 14:00.\n\nThe job held steady.", Chat::Chart::Marker.strip(text)
  end

  test "plain text drops a marker written inside a sentence, and one in backticks" do
    assert_equal "Memory of web climbed.", Chat::Chart::Marker.strip("Memory of web climbed {{chart:3f9a1c2e}}.")
    assert_equal "Memory of web climbed.", Chat::Chart::Marker.strip("Memory of web climbed `{{chart:3f9a1c2e}}`.")
  end

  test "plain text drops a marker that ends the answer" do
    assert_equal "Memory of web climbed.", Chat::Chart::Marker.strip("Memory of web climbed.\n\n{{chart:3f9a1c2e}}\n")
  end

  test "text without markers is left exactly as it was, trailing spaces and blank lines included" do
    text = "Line one  \nline two\n\n\n\nline three\n"

    assert_same text, Chat::Chart::Marker.strip(text)
    assert_nil Chat::Chart::Marker.strip(nil)
  end

  test "braces that are not a chart's marker stay" do
    text = "Templates read {{ name }} and {{chart:short}}."

    assert_equal text, Chat::Chart::Marker.strip(text)
    assert_empty Chat::Chart::Marker.handles_in(text)
  end

  test "the note on a tool result names each chart's marker and title, and says nothing when nothing was drawn" do
    web, job = record("Memory of web", "Memory of job")

    note = Chat::Chart::Marker.note([ web, job ])

    assert_includes note, "{{chart:#{web.handle}}} Memory of web"
    assert_includes note, "{{chart:#{job.handle}}} Memory of job"
    assert_nil Chat::Chart::Marker.note([])
  end

  private

  def record(*titles)
    Chat::Chart.record!(@chat, "call_1", titles.map do |title|
      { "title" => title, "unit" => "MB", "from" => @started.iso8601, "to" => (@started + 1.hour).iso8601,
        "series" => [ { "label" => "web-1", "points" => [ [ @started.iso8601, 1 ], [ (@started + 1.hour).iso8601, 2 ] ] } ] }
    end)
  end
end
