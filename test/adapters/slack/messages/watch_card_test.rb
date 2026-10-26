require "test_helper"

class Slack::Messages::WatchCardTest < ActiveSupport::TestCase
  RUN = "https://github.com/acme/firefight/actions/runs/99".freeze
  Checklist = Slack::Messages::Checklist

  test "a watch going is a live checklist of its steps named for what it is for, then Watching, then Stop, the run and the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).with("c1").returns("https://firefight.test/agent/c1")
    card = card_of(status: Chat::Watch::STATUS_ACTIVE, what: "Release <firefight> to production", why: "1 of 3 steps done. Northflank release run is running.",
                   link: RUN, conversation_id: "c1", steps: [
                     step_of("s1", "GitHub Release run", Chat::Watch::Step::STATUS_SUCCEEDED, "Succeeded after 4 minutes."),
                     step_of("s2", "Northflank release run", Chat::Watch::Step::STATUS_RUNNING, "Run #99 is running."),
                     step_of("s3", "Web rollout", Chat::Watch::Step::STATUS_WAITING, "Waits for Northflank release run.")
                   ])

    plan, standing, actions = Slack::Messages::WatchCard.build(card, rich: true)

    assert_equal [ "plan", "Release <firefight> to production" ], [ plan[:type], plan[:title] ]
    assert_equal [ [ "s1", "GitHub Release run", Checklist::COMPLETE ], [ "s2", "Northflank release run", Checklist::IN_PROGRESS ],
                   [ "s3", "Web rollout", Checklist::PENDING ] ],
                 plan[:tasks].map { |task| task.values_at(:task_id, :title, :status) }
    assert_equal [ "Succeeded after 4 minutes.", "Run #99 is running.", "Waits for Northflank release run." ],
                 plan[:tasks].map { |task| (task[:output] || task[:details]).dig(:elements, 0, :elements, 0, :text) }
    assert_equal ":eyes:  Watching", standing[:elements].sole[:text], "while it goes the steps say why, so the line is the state alone"
    stop, run, open = actions[:elements]
    assert_equal [ Identifiers::WATCH_STOP, "u1", "Stop" ], [ stop[:action_id], stop[:value], stop.dig(:text, :text) ]
    assert_equal "Stop watching?", stop.dig(:confirm, :title, :text)
    assert_equal "Halon stops watching this and says so here. It will not report on it again.", stop.dig(:confirm, :text, :text)
    assert_equal [ "Open the run", RUN ], [ run.dig(:text, :text), run[:url] ]
    assert_equal [ "Open the chat", "https://firefight.test/agent/c1" ], [ open.dig(:text, :text), open[:url] ]
    assert_equal "Watching: Release <firefight> to production. 1 of 3 steps done. Northflank release run is running.",
                 Slack::Messages::WatchCard.fallback(card)
  end

  test "a watch of one thing is a checklist of one task" do
    card = card_of(status: Chat::Watch::STATUS_ACTIVE, steps: [ step_of("s1", "Web deploy", Chat::Watch::Step::STATUS_WAITING, "Waiting for it to start.") ])

    plan, standing, actions = Slack::Messages::WatchCard.build(card, rich: true)

    assert_equal [ [ "Web deploy", Checklist::PENDING ] ], plan[:tasks].map { |task| task.values_at(:title, :status) }
    assert_equal ":eyes:  Watching", standing[:elements].sole[:text]
    assert_equal [ Identifiers::WATCH_STOP ], actions[:elements].map { |button| button[:action_id] }
  end

  test "each step's status is a task's: waiting, in progress, done or failed, and one skipped or no longer followed stays unticked" do
    statuses = {
      Chat::Watch::Step::STATUS_WAITING => Checklist::PENDING, Chat::Watch::Step::STATUS_RUNNING => Checklist::IN_PROGRESS,
      Chat::Watch::Step::STATUS_REPAIRING => Checklist::IN_PROGRESS, Chat::Watch::Step::STATUS_SUCCEEDED => Checklist::COMPLETE,
      Chat::Watch::Step::STATUS_FAILED => Checklist::ERROR, Chat::Watch::Step::STATUS_UNFOLLOWABLE => Checklist::PENDING,
      Chat::Watch::Step::STATUS_SKIPPED => Checklist::PENDING
    }
    assert_equal Chat::Watch::Step::STATUSES.sort, statuses.keys.sort
    card = card_of(status: Chat::Watch::STATUS_ACTIVE, steps: statuses.keys.map { |status| step_of(status, status.humanize, status, nil) })

    plan = Slack::Messages::WatchCard.build(card, rich: true).first

    assert_equal statuses.values, plan[:tasks].map { |task| task[:status] }
  end

  test "an ended watch keeps its steps, says how it ended and why, and offers only the run and the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).returns("https://firefight.test/agent/c1")
    {
      Chat::Watch::STATUS_SUCCEEDED => [ ":white_check_mark:", "Done" ], Chat::Watch::STATUS_FAILED => [ ":x:", "Failed" ],
      Chat::Watch::STATUS_TIMED_OUT => [ ":hourglass:", "Timed out" ], Chat::Watch::STATUS_STOPPED => [ ":octagonal_sign:", "Stopped" ]
    }.each do |status, (icon, state)|
      card = card_of(status: status, state: state, why: "Took 7 minutes & then some.", link: RUN, conversation_id: "c1",
                     steps: [ step_of("s1", "Web rollout", Chat::Watch::Step::STATUS_FAILED, "a924eed failed on web.") ])

      plan, standing, actions = Slack::Messages::WatchCard.build(card, rich: true)

      assert_equal [ "Deploy finished", Checklist::ERROR ], [ plan[:title], plan[:tasks].sole[:status] ]
      assert_equal "#{icon}  #{state}  ·  Took 7 minutes &amp; then some.", standing[:elements].sole[:text]
      assert_equal [ "Open the run", "Open the chat" ], actions[:elements].map { |button| button.dig(:text, :text) }
    end
  end

  test "an ended watch with nothing to open has no buttons" do
    blocks = Slack::Messages::WatchCard.build(card_of(status: Chat::Watch::STATUS_SUCCEEDED, state: "Done"), rich: true)

    assert_equal %w[plan context], blocks.map { |block| block[:type] }
  end

  test "a workspace that does not show plans gets the title by its mark, a line per step, the state and the buttons" do
    card = card_of(status: Chat::Watch::STATUS_ACTIVE, what: "Ship <main>",
                   steps: [ step_of("s1", "Web deploy", Chat::Watch::Step::STATUS_RUNNING, "Running & nearly there.") ])

    blocks = Slack::Messages::WatchCard.build(card, rich: false)

    assert_equal %w[section divider section context actions], blocks.map { |block| block[:type] }
    assert_equal ":eyes:  *Ship &lt;main&gt;*", blocks.first.dig(:text, :text)
    assert_equal ":hourglass_flowing_sand: Web deploy  _Running &amp; nearly there._", blocks.third.dig(:text, :text)
    assert_equal "Watching", blocks.fourth[:elements].sole[:text]
    assert_equal [ Identifiers::WATCH_STOP ], blocks.fifth[:elements].map { |button| button[:action_id] }
  end

  test "how it ended is one short line of its own, so the person hears it, led by its mark" do
    card = card_of(status: Chat::Watch::STATUS_SUCCEEDED, state: "Done", what: "Ship main", why: "Took 7 minutes. web is serving 7676c83.")

    assert_equal [ { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  *Done: Ship main.* Took 7 minutes. web is serving 7676c83." } } ],
                 Slack::Messages::WatchCard.ended(card)
    assert_equal "Done: Ship main. Took 7 minutes. web is serving 7676c83.", Slack::Messages::WatchCard.fallback(card)
  end

  private

  def card_of(status:, state: "Watching", what: "Deploy finished", why: "Web deploy is running.", link: nil, conversation_id: nil, steps: [])
    Conversation::Watches::Card.new(watch_id: "w1", update_id: "u1", status: status, state: state, what: what, why: why, link: link,
                                    conversation_id: conversation_id, steps: steps)
  end

  def step_of(id, label, status, line) = Conversation::Watches::CardStep.new(id: id, label: label, status: status, line: line)
end
