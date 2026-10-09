# Something Halon is watching for this chat, or watched: what it follows, how long it watches, each step as it stands, and
# how it ended. Whether the viewer may stop it ships as a blocked reason, so the card decides nothing.
class AgentChatWatchSerializer < BaseSerializer
  object_as :watch

  type :string
  def id
    watch.id
  end

  # What is watched, as the person put it, such as release run #46.
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

  # Such as "Watching: release run #46, up to 40 min".
  type :string
  def headline = Chat::Watch::Shown.headline(watch)

  type :string, optional: true
  def outcome
    watch.outcome
  end

  # Where the limit came from, such as "It usually takes about 18 minutes."
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

  type "{ id: string; label: string; status: #{Chat::Watch::Step::STATUSES.map(&:inspect).join(" | ")}; state: string | null }[]"
  def steps
    watch.steps.map { |step| { id: step.id, label: step.label, status: Chat::Watch::Shown.step_status(step), state: Chat::Watch::Shown.step_state(step) } }
  end

  type :string, optional: true
  def stop_blocked_reason
    watch.stop_blocked_reason(options[:member]) if watch.active?
  end
end
