# Something Halon is watching for this chat, or watched: what it follows, how long it watches, each step as it stands, and
# how it ended. Whether the viewer may stop it ships as a blocked reason, so the card decides nothing.
class AgentChatWatchSerializer < BaseSerializer
  object_as :watch

  type :string
  def id
    watch.id
  end

  # What it waits on, such as Deploy finished.
  type :string
  def title
    watch.title
  end

  # Why the person wanted it, in their words, such as get releases deploying through the webhook again.
  type :string, optional: true
  def purpose
    watch.purpose
  end

  type Chat::Watch::STATUSES.map(&:inspect).join(" | ")
  def status
    watch.status
  end

  # Such as Watch "Deploy finished" while it runs, and Watch "Deploy finished": done once it ended.
  type :string
  def headline = Chat::Watch::Shown.headline(watch)

  # Its ceiling on reads and how many it made, such as "Reads at most 120 times an hour. 14 reads so far."
  type :string
  def reads = Chat::Watch::Shown.reads(watch)

  type :string, optional: true
  def outcome
    watch.outcome
  end

  # How long it watches and where that came from, such as "Up to 40 min. It usually takes about 18 minutes."
  type :string, optional: true
  def basis
    Chat::Watch::Shown.basis(watch)
  end

  type :string
  def expires_at
    watch.expires_at.utc.iso8601
  end

  # Placed among the chat's messages by when it started.
  type :string
  def at
    watch.created_at.utc.iso8601(3)
  end

  # url is the page of the run or what the step follows, when the provider gave one.
  type "{ id: string; label: string; status: #{Chat::Watch::Step::STATUSES.map(&:inspect).join(" | ")}; state: string | null; url: string | null }[]"
  def steps
    watch.steps.map do |step|
      { id: step.id, label: step.label, status: Chat::Watch::Shown.step_status(step), state: Chat::Watch::Shown.step_state(step), url: step.run_url }
    end
  end

  type :string, optional: true
  def stop_blocked_reason
    watch.stop_blocked_reason(options[:member]) if watch.active?
  end
end
