# What the shared tools ask of whoever they run for, for one helper. Every call goes through the asking turn or run, so
# it is authorized as the same principal, ledgered under the same source and, in a run, recorded as a numbered step the
# answer can cite. It only reads, never waits for a person and keeps nothing to run later.
class Chat::Helpers::Agent
  attr_reader :helper

  # parent is the asking turn or run, a copy of its own for this helper's thread.
  def initialize(helper, parent:)
    @helper = helper
    @parent = parent
  end

  delegate :acting_principal, :workspace, :incident, :code_box_key, to: :@parent

  def chat = @helper.own_chat
  def chat_owner = @helper
  def reads_only? = true
  def changes_memory? = false
  def uses_skills? = true
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false
  def hold!(*, **) = false
  def pack_refused!(_action_key, _tool_call_id) = nil

  def refusal(action_key)
    "Not allowed: whoever Halon acts for cannot use #{action_key}. Say so in your report and read what you can with the other tools."
  end

  # A chart is for the person, so it goes with the asking chat under the run_helpers step, where the page, a thread and a
  # run's story already draw charts, rather than with a helper's own chat that nobody reads.
  def charts_kept_on(_tool_call_id) = [ @helper.chat, @helper.tool_call_id ]

  def mark_step_failed!(position, kind) = @parent.mark_step_failed!(position, kind)

  # A run keeps which helper made each step, and a chat's turn has nothing to keep it on.
  def tool_call(**arguments, &) = @parent.tool_call(**arguments, helper: @helper, &)
end
