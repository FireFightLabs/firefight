require "test_helper"

class Slack::MessageTextTest < ActiveSupport::TestCase
  def convert(text, names: {}) = Slack::MessageText.convert(text, names: names)

  test "a mention reads as the person's name, and someone unknown keeps a readable stand in" do
    assert_equal "@Alice Smith can you check, @bob? Thanks @someone", convert("<@U1> can you check, <@U2|bob>? Thanks <@U9>", names: { "U1" => "Alice Smith" })
  end

  test "a name is shown exactly as it is written" do
    assert_equal "@*Al* <b> & co", convert("<@U1>", names: { "U1" => "*Al* <b> & co" })
  end

  test "channels, broadcasts and groups read as their names" do
    assert_equal "@here see #incidents and @oncall", convert("<!here> see <#C1|incidents> and <!subteam^S1|@oncall>")
  end

  test "a link reads as its label with the address after it, or the address alone" do
    assert_equal "See the dashboard (https://grafana.example.com/d/1?a=1&b=2) and https://status.example.com",
                 convert("See <https://grafana.example.com/d/1?a=1&amp;b=2|the dashboard> and <https://status.example.com>")
  end

  test "a link Slack made from an address someone typed reads as that address once" do
    assert_equal "status.example.com and ops@example.com", convert("<http://status.example.com|status.example.com> and <mailto:ops@example.com|ops@example.com>")
  end

  test "bold, italics and strikes read as their words" do
    assert_equal "rolled back the deploy maybe, really", convert("*rolled back* _the deploy_ ~maybe~, *_really_*")
  end

  test "marks that are not formatting stay as typed" do
    assert_equal "5 * 3, a*b*c and snake_case_name", convert("5 * 3, a*b*c and snake_case_name")
  end

  test "code reads as what was typed, without its backticks" do
    assert_equal "run kubectl get pods then\nif a < b\n  go", convert("run `kubectl get pods` then\n```\nif a &lt; b\n  go\n```")
  end

  test "escaped characters read as typed" do
    assert_equal "> errors < 5% & falling", convert("&gt; errors &lt; 5% &amp; falling")
  end

  test "standard emoji read as themselves, and the workspace's own and any in code stay as typed" do
    assert_equal "✅ rolled back 👍🏼 :partyparrot: :rocket:", convert(":white_check_mark: rolled back :+1::skin-tone-3: :partyparrot: `:rocket:`")
  end

  test "a shortcode in a link's label reads as the emoji" do
    assert_equal "🚀 release (https://example.com/:rocket:)", convert("<https://example.com/:rocket:|:rocket: release>")
  end

  test "for a model, a person, a channel and a group keep their ids beside their names" do
    assert_equal "@Ana Lee (U1) and @bob (U2) and @U9, see #incidents (C1) or #C2, ping @oncall (S1) @here",
                 Slack::MessageText.convert("<@U1> and <@U2|bob> and <@U9>, see <#C1|incidents> or <#C2>, ping <!subteam^S1|@oncall> <!here>",
                                            names: { "U1" => "Ana Lee" }, for_model: true)
  end

  test "for a model, code keeps its backticks and the rest reads as Slack shows it" do
    assert_equal "rolled back 🔥 & ran `kubectl get pods`\n```\nif a < b\n```", Slack::MessageText.convert("*rolled back* :fire: &amp; ran `kubectl get pods`\n```if a &lt; b```", for_model: true)
  end

  test "an empty message stays empty" do
    assert_equal "", convert(nil)
  end
end
