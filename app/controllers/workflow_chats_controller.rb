# Asking Halon from beside a workflow's canvas. The chat is the person's own, started with the workflow as what it is
# about, so Halon is told which workflow is open and its changes land on the canvas as suggestions. It is listed with
# the person's other chats too, where it opens in full.
class WorkflowChatsController < InertiaController
  include WorkflowCanvas
  include RequiresAgent

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create stop]

  before_action :require_agent!

  NOTHING_ASKED = "Say something first.".freeze
  FRESH_PARAM = "fresh"

  # A question joins the canvas's chat, or starts one when there is none or the person asked for a new one.
  def create
    question = params[:question].to_s.strip
    return back_to_canvas(alert: NOTHING_ASKED) if question.blank?

    chat = ActiveModel::Type::Boolean.new.cast(params[FRESH_PARAM]) ? nil : workflow_chat
    return start(question) unless chat

    blocked = chat.ask_blocked_reason
    return back_to_canvas(alert: blocked) if blocked

    Conversation::Asking.ask(chat, question, asker: current_membership)
    back_to_canvas
  end

  # The answer ends with Stopped once the worker stops.
  def stop
    chat = workflow_chat
    blocked = chat ? chat.stop_blocked_reason : Conversation::NOTHING_TO_STOP
    return back_to_canvas(alert: blocked) if blocked

    chat.request_stop!
    back_to_canvas(notice: Conversation::STOPPING)
  end

  private

  def start(question)
    Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: question, subject: workflow)
    back_to_canvas
  end

  def workflow_chat = Conversation.beside(workflow, current_membership)

  def refuse_without_agent(reason) = back_to_canvas(alert: reason)
end
