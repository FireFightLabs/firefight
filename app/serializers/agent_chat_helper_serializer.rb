# A helper Halon handed one check to in this chat, drawn under the run_helpers step that started it: its title and brief,
# where it got to, every step it took, and what it reported or why it ended without a report.
class AgentChatHelperSerializer < BaseSerializer
  object_as :helper

  type :string
  def id = helper.id

  # The run_helpers call it came from, which the step on the page is keyed by.
  type :string
  def tool_call_id = helper.tool_call_id

  type :string
  def title = helper.title

  type :string
  def brief = helper.brief

  type Chat::Helper::STATUSES.map(&:inspect).join(" | ")
  def status = helper.status

  type :string, optional: true
  def report = (helper.report if helper.reported?)

  type :string, optional: true
  def ended_because = helper.ended_because

  type :string
  def started_at = helper.started_at.utc.iso8601(3)

  type :string, optional: true
  def finished_at = helper.finished_at&.utc&.iso8601(3)

  # Each step it took, the same shape the chat's own steps take, with what came back once it did.
  type "{ key: string; title: string; headline: string; asked: [string, string][]; status: string; " \
       "outcome: #{AgentChatMessageSerializer::OUTCOME_TYPE} | null }[]"
  def steps
    chat = helper.own_chat
    return [] unless chat

    calls = chat.tool_calls.includes(:result).order(:created_at).to_a
    calls.filter_map do |call|
      step = Chat::Tools.step(call.name, call.arguments, workspace: helper.workspace)
      next unless step

      status = AgentChatMessageSerializer.step_status(call)
      # A helper that ended while a call was open will never hear back from it.
      status = Conversation::LiveDelivery::STATUS_CANCELLED if status == Conversation::LiveDelivery::STATUS_RUNNING && !helper.running?
      { key: call.tool_call_id, title: step.title, headline: step.headline, asked: step.asked, status: status,
        outcome: (Chat::StepOutcome.for_call(call, chat)&.to_h if AgentChatMessageSerializer::FINISHED.include?(status)) }
    end
  end
end
