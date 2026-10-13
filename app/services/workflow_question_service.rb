# Where a workflow's Ask a person question, or a Manual step's task, is shown and answered. Everyone asked gets it in a
# direct message, a task for anyone is posted in its channel, and it is on the run's page too. The first answer, from
# any place, carries the step on (DefinedWorkflow.deliver!), and every message it was sent in is redrawn once it is
# answered or withdrawn.
class WorkflowQuestionService
  Answered = Data.define(:ok, :words)

  ANSWERED = "Your answer was sent.".freeze
  GONE = "This question is gone.".freeze

  # Sent to each person asked once, however often the job runs, or posted once in its channel when anyone may answer. A
  # question already settled is redrawn instead.
  def self.ask!(question)
    return redraw!(question) unless question.open?

    adapter = WorkspaceAdapter.for(question.workspace)
    return post_in_channel!(question, adapter) if question.open_to_anyone?

    told = question.notifications.map { |notification| notification["member_id"] }
    question.asked_members.where.not(id: told).find_each do |member|
      next if member.platform_user_id.blank?

      sent = adapter.post_workflow_question(user_id: member.platform_user_id, question: question)
      next if question.add_notification!(channel_id: sent[:channel_id], message_id: sent[:message_id], member_id: member.id)

      adapter.update_workflow_question(channel_id: sent[:channel_id], message_id: sent[:message_id], question: question)
    rescue AdapterError => error
      Rails.logger.warn({ event: "workflow_question.ask_failed", question_id: question.id, error: error.class.name }.to_json)
    end
  end

  def self.post_in_channel!(question, adapter)
    return if question.channel_id.blank? || question.posted_in_channel?

    sent = adapter.post_workflow_question_in_channel(channel_id: question.channel_id, question: question)
    return if question.add_notification!(channel_id: sent[:channel_id], message_id: sent[:message_id], member_id: nil)

    adapter.update_workflow_question(channel_id: sent[:channel_id], message_id: sent[:message_id], question: question)
  rescue AdapterError => error
    Rails.logger.warn({ event: "workflow_question.post_failed", question_id: question.id, error: error.class.name }.to_json)
  end
  private_class_method :post_in_channel!

  # A task's Done, from a platform's button, which finishes a task that collects no note in one click.
  def self.finish_by_id!(workspace, id, by:)
    question = workspace_question(workspace, id)
    return Answered.new(ok: false, words: GONE) unless question&.task?

    answer!(question, by: by)
  end

  # The question a platform's button names, and why this member cannot answer it, or nil when they can.
  def self.for_answer(workspace, id, member)
    question = workspace_question(workspace, id)
    question ? [ question, question.answer_blocked_reason(member) ] : [ nil, GONE ]
  end

  # One of its choices by its place, from a platform's button.
  def self.choose_by_id!(workspace, id, index, by:)
    question = workspace_question(workspace, id)
    return Answered.new(ok: false, words: GONE) unless question

    answer!(question, by: by, choice: index && index >= 0 ? question.choice_keys[index] : nil)
  end

  # The person's answer: one of the choices, the form's fields, or both. A refusal says why in the model's words.
  def self.answer!(question, by:, choice: nil, values: {})
    blocked = question.answer_blocked_reason(by) || question.answer_problem(choice, values)
    return Answered.new(ok: false, words: blocked) if blocked
    return Answered.new(ok: false, words: question.reload.answer_blocked_reason(by) || GONE) unless question.answer!(by: by, choice: choice, values: values)

    delivered = question.answer.merge("by" => by.actor_display_name)
    DefinedWorkflow.deliver!(question.engine_step_id, question.delivery_key, delivered)
    redraw!(question)
    Answered.new(ok: true, words: ANSWERED)
  end

  # Withdrawn because its run stopped waiting for it, such as a run cancelled while it waited.
  def self.withdraw!(question)
    redraw!(question) if question.expire!
  end

  def self.redraw!(question)
    adapter = WorkspaceAdapter.for(question.workspace)
    question.notifications.each do |notification|
      adapter.update_workflow_question(channel_id: notification["channel_id"], message_id: notification["message_id"], question: question)
    rescue AdapterError => error
      Rails.logger.warn({ event: "workflow_question.redraw_failed", question_id: question.id, error: error.class.name }.to_json)
    end
  end

  def self.workspace_question(workspace, id) = Workflow::Run::Question.find_by(id: id, workspace: workspace)
  private_class_method :workspace_question
end
