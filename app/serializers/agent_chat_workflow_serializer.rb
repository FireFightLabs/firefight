# A workflow Halon made in this chat, as its card shows it: when it runs, how it stands, how its last run went and what
# the person reading can do with it, each with why they cannot.
class AgentChatWorkflowSerializer < BaseSerializer
  object_as :workflow

  type :string
  def id = workflow.id

  attributes(name: { type: :string })

  type :string
  def state = workflow.state

  type :string
  def trigger_words = workflow.trigger_words

  type :boolean
  def one_off = workflow.one_off?

  type :string, optional: true
  def next_run_at = workflow.next_run_at&.iso8601

  # When it was made, which places the card after the turn that made it.
  type :string
  def at = workflow.created_at.iso8601(3)

  type "{ id: string; status: string; at: string; error?: string } | null"
  def last_run
    run = workflow.last_chat_run
    run && { id: run.id, status: run.status, at: (run.finished_at || run.created_at).iso8601, error: run.error }.compact
  end

  # Said while it waits for an admin to publish it.
  type :string, optional: true
  def waiting = ("It waits for a workspace admin to publish it." unless workflow.live?)

  type "{ action: #{Workflow::CHAT_ACTIONS.map(&:inspect).join(' | ')}; blockedReason: string | null }[]"
  def offers
    workflow.chat_offers(options[:member]).map { |offer| { action: offer.action, blockedReason: offer.blocked_reason } }
  end
end
