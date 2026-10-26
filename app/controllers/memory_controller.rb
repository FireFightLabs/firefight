# What the workspace remembers and the instructions people give Halon, where people review, correct and write them.
class MemoryController < InertiaController
  authorizes Ability::Action::RESOURCE_MEMORY,
    read: %i[index],
    create: %i[create_memory],
    update: %i[confirm_memory correct_memory reject_memory destroy_memory approve_lesson edit_lesson turn_down_lesson]
  authorizes Ability::Action::RESOURCE_CATALOG, update: %i[create_instruction update_instruction destroy_instruction]

  TAB_QUERY = "tab"
  TAB_MEMORIES = "memories"
  TAB_INSTRUCTIONS = "instructions"
  TAB_LESSONS = "lessons"
  REVIEWS_CHECK_IT = "Pull request reviews check it from now on.".freeze
  STRICT_CHECKS = "Pull request reviews check it from now on, and fail a check on a pull request that goes against it.".freeze
  CHANGED_FIRST = "Someone changed these instructions first. Their version is shown now."

  include RequiresAgent
  before_action :require_agent!

  def index
    memories = self.memories.includes(:subject, :source, :added_by, :confirmed_by, :rejected_by).order(updated_at: :desc)

    render inertia: "memory/index", props: {
      memories: ChatMemorySerializer.many(memories),
      lessons: ChatLessonSerializer.many(lessons, member: current_membership),
      instructions: ChatInstructionSerializer.many(Chat::Instruction.with_history(current_workspace, principal: current_membership)),
      subjects: MemorySubjectOptionSerializer.many(Chat::Memory.subject_choices(current_workspace, principal: current_membership))
    }
  end

  def create_memory
    memory = Chat::Memory.written_by!(current_membership, text: params[:text].to_s.strip, subject: subject_param)
    redirect_to memory_path, notice: "Remembered#{" about #{memory.about}" if memory.about}. Halon uses it from now on."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to memory_path, alert: error.record.errors.full_messages.to_sentence
  end

  # Deciding works from the Memory page and from a card in a chat, and each goes back to where it was pressed.
  def confirm_memory
    memory = memories.find(params[:id])
    return redirect_back_or_to(memory_path, alert: memory.confirm_blocked_reason) unless memory.confirm_or_approve!(by: current_membership)

    kept = memory.contradicted_by ? "Kept as still right. Halon stops using what contradicted it." : "Confirmed. Halon now reads it as confirmed by you."
    kept = "#{kept} #{REVIEWS_CHECK_IT}" if memory.approved_lesson?
    redirect_back_or_to memory_path, notice: kept
  end

  def correct_memory
    memory = memories.find(params[:id])
    replacement = memory.correct!(by: current_membership, reason: params[:reason].to_s.strip, correction: params[:text].to_s.strip)
    return redirect_back_or_to(memory_path, alert: memory.reject_blocked_reason) unless replacement

    corrected = "Corrected. Halon keeps the old wording as rejected so it does not learn it again."
    redirect_back_or_to memory_path, notice: replacement.approved_lesson? ? "#{corrected} #{REVIEWS_CHECK_IT}" : corrected
  rescue ActiveRecord::RecordInvalid => error
    redirect_back_or_to memory_path, alert: error.record.errors.full_messages.to_sentence
  end

  def reject_memory
    memory = memories.find(params[:id])
    return redirect_back_or_to(memory_path, alert: memory.reject_blocked_reason) unless memory.reject!(by: current_membership, reason: params[:reason].to_s.strip)

    instead = memory.replaced_by
    rejected = instead ? "Marked not right. Halon now remembers \"#{instead.text}\" instead, confirmed by you." : "Rejected. Halon stops using it and does not learn it again."
    redirect_back_or_to memory_path, notice: rejected
  end

  def destroy_memory
    memory = memories.find(params[:id])
    memory.destroy!

    redirect_to memory_path, notice: "Deleted. #{memory.delete_consequence}"
  end

  def approve_lesson
    lesson = lessons.find(params[:id])
    return redirect_to(lessons_page, alert: lesson.approve_blocked_reason(current_membership)) unless lesson.approve!(by: current_membership, strict: strict_param)

    redirect_to lessons_page, notice: "Approved the #{lesson.source.identifier} lesson. #{lesson.strict ? STRICT_CHECKS : REVIEWS_CHECK_IT}"
  end

  def edit_lesson
    lesson = lessons.find(params[:id])
    edited = lesson.edit_lesson!(by: current_membership, text: params[:text].to_s.strip, strict: strict_param)
    return redirect_to(lessons_page, alert: lesson.edit_lesson_blocked_reason(current_membership)) unless edited

    redirect_to lessons_page, notice: "Saved the #{lesson.source.identifier} lesson. #{edited.strict ? STRICT_CHECKS : REVIEWS_CHECK_IT}"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to lessons_page, alert: error.record.errors.full_messages.to_sentence
  end

  def turn_down_lesson
    lesson = lessons.find(params[:id])
    turned_down = lesson.turn_down!(by: current_membership, reason: params[:reason].to_s.strip)
    return redirect_to(lessons_page, alert: lesson.turn_down_blocked_reason(current_membership)) unless turned_down

    redirect_to lessons_page, notice: "Turned down the #{lesson.source.identifier} lesson. Reviews and Halon stop using it."
  end

  def create_instruction
    note = Chat::Instruction.create!(workspace: current_workspace, scope: subject_param, text: params[:text].to_s.strip, added_by: current_membership)
    redirect_to instructions_page, notice: "Saved instructions for #{note.place}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to instructions_page, alert: error.record.errors.full_messages.to_sentence
  end

  def update_instruction
    note = instructions.current.find(params[:id]).revise!(text: params[:text].to_s.strip, by: current_membership)
    return redirect_to(instructions_page, alert: CHANGED_FIRST) unless note

    redirect_to instructions_page, notice: "Updated instructions for #{note.place}. The earlier wording is kept as history."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to instructions_page, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy_instruction
    note = instructions.current.find(params[:id])
    return redirect_to(instructions_page, alert: CHANGED_FIRST) unless note.retire!

    redirect_to instructions_page, notice: "Removed the instructions for #{note.place}. They are kept as history."
  end

  private

  def instructions_page = memory_path(TAB_QUERY => TAB_INSTRUCTIONS)

  def lessons_page = memory_path(TAB_QUERY => TAB_LESSONS)

  # What an incident taught, apart from wordings an edit or a correction replaced, which the Memories tab keeps.
  def lessons = memories.lessons.where(replaced_by_id: nil).includes(:subject, :approved_by, :confirmed_by, :rejected_by, source: { incident_role_assignments: :incident_role })

  def strict_param = ActiveModel::Type::Boolean.new.cast(params[:strict]) || false

  # A memory about a resource outside the person's map reach is not on their page, and deciding on one finds nothing.
  def memories = Chat::Memory.visible_to(current_membership, current_workspace)

  # Instructions follow the same reach, so editing or removing one about a hidden resource finds nothing. The handbook is
  # edited on its own page.
  def instructions = Chat::Instruction.visible_to(current_membership, current_workspace).for_places

  def subject_param = Chat::Memory.subject_for_key(current_workspace, params[:subject], principal: current_membership)
end
