require "test_helper"

class Chat::ChartTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    @started = Time.utc(2026, 9, 25, 14, 0)
  end

  test "the charts in a tool result are kept with the chat, and a malformed one is left out" do
    Chat::Chart.record!(@chat, "call_1", [ chart_hash("5xx responses of checkout"), { "title" => "broken", "from" => "not a time" } ])

    kept = @chat.charts.sole
    assert_equal "call_1", kept.tool_call_id
    assert_equal "5xx responses of checkout", kept.title
    assert_equal 2, kept.series.size
  end

  test "a chart draws as a PNG with its title, unit and every series" do
    Chat::Chart.record!(@chat, "call_1", [ chart_hash("5xx responses of checkout") ])
    image = Chat::Chart::Image.new(@chat.charts.sole)

    png = image.png
    texts = image.labels.map(&:first)

    assert png.start_with?("\x89PNG".b)
    assert_includes texts, "5xx responses of checkout"
    assert_includes texts, "checkout-7f9c"
    assert_includes texts, "checkout-2b1d"
    File.binwrite(ENV["CHART_PREVIEW"], png) if ENV["CHART_PREVIEW"]
  end

  test "a chart over several days marks its axis with dates, gives its range both ends' days, and keeps long names whole" do
    week = chart_hash("Memory of job").merge("to" => (@started + 7.days).iso8601)
    week["series"] = [ "job-5646f5b664-pq8pz", "job-5fc548d4b8-7vbdt", "job-7a1c2e9d01-xk2mt" ].map do |label|
      { "label" => label, "points" => [ [ @started.iso8601, 50 ], [ (@started + 7.days).iso8601, 55 ] ] }
    end
    Chat::Chart.record!(@chat, "call_1", [ week ])
    image = Chat::Chart::Image.new(@chat.charts.sole)

    texts = image.labels.map(&:first)

    assert_includes texts, "Sep 25 14:00 to Oct 2 14:00 UTC"
    assert_includes texts, "Sep 27"
    assert_includes texts, "job-5646f5b664-pq8pz"
    assert_includes texts, "job-7a1c2e9d01-xk2mt"
    assert image.png.start_with?("\x89PNG".b)
    File.binwrite(ENV["CHART_PREVIEW"].sub(".png", "-week.png"), image.png) if ENV["CHART_PREVIEW"]
  end

  private

  def chart_hash(title)
    points = ->(high) { (0..59).map { |minute| [ (@started + minute.minutes).iso8601, minute > 40 ? high + (minute % 5) : minute % 3 ] } }
    {
      "title" => title, "unit" => "count", "from" => @started.iso8601, "to" => (@started + 59.minutes).iso8601,
      "series" => [ { "label" => "checkout-7f9c", "points" => points.call(30) }, { "label" => "checkout-2b1d", "points" => points.call(22) } ]
    }
  end
end
