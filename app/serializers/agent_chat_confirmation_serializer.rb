# A call the agent paused on, put to the person as a question.
class AgentChatConfirmationSerializer < BaseSerializer
  object_as :tool_call

  type :string
  def toolCallId
    tool_call.tool_call_id
  end

  # The tool's own name, so allowing one call for the rest of the chat can answer the others asked about it, and shown
  # under Details.
  type :string
  def tool
    tool_call.name
  end

  # The request, such as "Halon wants to: pause dev-web", the card's title.
  type :string
  def heading
    confirmation.heading
  end

  # The one line under it: what the call changes or why Halon asks, free of code and ids. Absent when nothing is known.
  type :string, optional: true
  def line
    confirmation.line
  end

  # Said with the line when outside text holding the change's own values was read before asking. Absent otherwise.
  type :string, optional: true
  def caution
    confirmation.caution
  end

  # What will happen, in plain words, such as "Pause dev-web", under Details and once answered.
  type :string
  def title
    confirmation.title
  end

  # Where it happens, such as "Northflank, project firefight", under Details. Absent when the title says it.
  type :string, optional: true
  def label
    confirmation.label
  end

  # What it does and how to put it back when that is known, under Details. Absent when the agent wrote nothing beyond the title.
  type :string, optional: true
  def summary
    confirmation.summary
  end

  # What the tool was given, shown under Details.
  type "string[][]"
  def asked
    confirmation.asked
  end

  # Whether Allow for the rest of this chat is offered, which it is not once something was read from outside.
  type :boolean
  def allowable
    confirmation.allowable?
  end

  # One sentence naming where outside text holding the change's own values came from. Absent when nothing read holds
  # any, so the warning shows only when it means something.
  type :string, optional: true
  def read_lead
    confirmation.read_lead
  end

  # Heads what was read from outside before the call was asked, under Details. Absent when nothing was.
  type :string, optional: true
  def read_heading
    confirmation.read_heading
  end

  type "string[][]"
  def read_rows
    confirmation.read_rows
  end

  # Heads the reads from the call's turn Halon named as showing the change will help. Absent when it named none.
  type :string, optional: true
  def support_lead
    confirmation.support_lead
  end

  # Each read Halon named: what it said the read showed, with the read as its source, or the read alone.
  type "{ text: string; source: string | null }[]"
  def support_points
    confirmation.support_points.map(&:to_h)
  end

  # What the call touches beyond its arguments, such as the rows a statement changes or who started what it stops.
  type "string[][]"
  def safeguards
    confirmation.safeguards
  end

  # When a change customers feel may be undone, in time order from never. Empty for any other call.
  type "{ value: string; label: string }[]"
  def expires
    confirmation.expires.map(&:to_h)
  end

  # The time chosen so far, which the choice starts on. Absent for any other call.
  type :string, optional: true
  def chosen_expiry
    confirmation.chosen_expiry
  end

  # What the undo choice is labelled, such as "Start it again automatically". Absent for any other call.
  type :string, optional: true
  def undo_label
    confirmation.undo_label
  end

  # The page a browser send goes from, as the check that stopped before it saw it, served under the chat. Absent for any
  # other call, and when the controller names no address for it.
  type :string, optional: true
  def page_path
    page = confirmation.page
    page && options[:screenshot_path]&.call(page)
  end

  type :string, optional: true
  def page_caption = confirmation.page&.caption

  private

  def confirmation = memo.fetch(:confirmation) { Chat::Tools.confirmation(tool_call) }
end
