require "test_helper"

class Slack::MessageMarkdownTest < ActiveSupport::TestCase
  def convert(text, names: {}) = Slack::MessageMarkdown.convert(text, names: names)

  test "a code block written on one line becomes a fenced block" do
    assert_equal "Look: \n```\nCustomers are seeing 502s\n```", convert("Look: ```Customers are seeing 502s```")
    assert_equal "```\nCustomers are seeing 502s\n```", convert("```Customers are seeing 502s```")
  end

  test "a code block keeps its lines and shows what was typed" do
    assert_equal "```\nif a < b\n  go\n```", convert("```\nif a &lt; b\n  go\n```")
  end

  test "bold uses two asterisks, while italics, strikes and inline code read the same" do
    assert_equal "**rolled back** _the deploy_ ~maybe~ `kubectl get pods`", convert("*rolled back* _the deploy_ ~maybe~ `kubectl get pods`")
  end

  test "an asterisk that is not bold stays as typed" do
    assert_equal "5 * 3 and a*b*c", convert("5 * 3 and a*b*c")
  end

  test "links read as their label, or their address when they have none" do
    assert_equal "See [the dashboard](<https://grafana.example.com/d/1?a=1&b=2>) and [https://status.example.com](<https://status.example.com>)",
                 convert("See <https://grafana.example.com/d/1?a=1&amp;b=2|the dashboard> and <https://status.example.com>")
  end

  test "a mention reads as the person's name, and someone unknown keeps a readable stand in" do
    assert_equal "@Alice Smith can you check, @bob?", convert("<@U1> can you check, <@U2|bob>?", names: { "U1" => "Alice Smith" })
    assert_equal "ask @someone", convert("ask <@U9>")
  end

  test "channels, broadcasts and groups read as their names" do
    assert_equal "@here see #incidents and @oncall", convert("<!here> see <#C1|incidents> and <!subteam^S1|@oncall>")
  end

  test "a quoted line stays a quote" do
    assert_equal "> the error rate is back\n> since 14:10\n\nAgreed", convert("&gt; the error rate is back\n&gt; since 14:10\nAgreed")
  end

  test "text markdown would read as markup stays as typed" do
    assert_equal "\\# not a heading, \\[not a link\\](x) and a &lt;b&gt; tag", convert("# not a heading, [not a link](x) and a &lt;b&gt; tag")
  end

  test "a name with markup in it is shown as written" do
    assert_equal "@\\*Al\\* &lt;b&gt;", convert("<@U1>", names: { "U1" => "*Al* <b>" })
  end

  test "lists the people a message mentions" do
    assert_equal [ "U1", "U2" ], Slack::MessageMarkdown.mentioned_ids("<@U1> <@U2|bob> <@U1>")
  end
end
