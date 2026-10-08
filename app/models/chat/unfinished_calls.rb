# A provider refuses a chat with anything but results between a call and the next message, so a call left without its
# result would make it refuse every later question. A call is left that way by a worker killed while it ran, or by the
# person asking something new while a call waited for them to confirm it.
module Chat::UnfinishedCalls
  # What the model reads for the call, and what its step shows.
  INTERRUPTED = "Interrupted before it finished, so this call did not complete and nothing came back. Whether a change " \
                "it was making took effect is unknown.".freeze
  NOT_CONFIRMED = "Not run. The person asked something else instead of confirming it. Ask them again only if it is still needed.".freeze

  # Results are placed by time just after the call, and the database keeps microseconds.
  TICK = Rational(1, 1_000_000)

  # Only whoever holds the run calls this, the reply job under its lock or a run under its lease, so no call it closes is
  # still running. A call waiting for the person, or confirmed and about to run, is left while nothing was said after it.
  # The row lock and the second look at each call make a second close add nothing.
  # before limits it to calls asked before then, for a sweep that found the turn's job gone, since a turn started after
  # that is not its to touch.
  def close_unfinished_calls!(before: nil)
    closed = with_lock do
      sent = sent_messages.reload.includes(:ruby_llm_tool_calls).to_a
      sent.each_with_index.flat_map do |message, index|
        later = sent.drop(index + 1)
        results = later.take_while { |follower| follower.role == Chat::Message::ROLE_TOOL }
        close_calls_of(message, after: results.last || message, moved_on: later.size > results.size, before: before)
      end
    end
    reload if closed.any?
    closed
  end

  private

  def close_calls_of(message, after:, moved_on:, before:)
    open = message.ruby_llm_tool_calls.select { |call| call.result_id.nil? && (before.nil? || call.created_at < before) }.sort_by(&:created_at)
    open.select { |call| moved_on || call.approval.nil? }.each_with_index.map do |call, index|
      waiting = call.approval == Chat::APPROVAL_REQUESTED
      result = messages.create!(
        role: Chat::Message::ROLE_TOOL, content: waiting ? NOT_CONFIRMED : INTERRUPTED,
        created_at: after.created_at + ((index + 1) * TICK)
      )
      call.update!(result: result, **(waiting ? { approval: Chat::APPROVAL_WITHDRAWN } : { failed: true, failure_kind: Chat::StepOutcome::FAILURE_ERROR }))
      call
    end
  end
end
