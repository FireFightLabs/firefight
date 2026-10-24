# What starting a watch asks of the turn that starts it, answered for a workflow step, so a Watch step starts exactly
# the watch Halon keeps in a chat. The watch belongs to a chat owned by the step's row, reads as whoever the run acts as,
# and reports its end to the step instead of to a person.
class Workflow::WatchHost
  # The place a watch is kept, where a chat's turn would hand its conversation.
  Place = Data.define(:record, :chat_record) do
    def id = record.id
    def personal? = false
    def thread_id = nil
    def channel_id = nil
    def incident = nil
    def incident_id = nil
    def code_box_key = record.code_box_key
    def ledger_context = record.ledger_context
  end

  attr_reader :workspace, :chat

  def initialize(run:, record:, principal:)
    @workspace = run.workspace
    @record = record
    @principal = principal
    @chat = Chat.find_by(owner: record) || Chat.open!(owner: record, workspace: @workspace,
                                                      model_choice: FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace))
  end

  def asker = @principal

  def conversation = Place.new(record: @record, chat_record: @chat)
end
