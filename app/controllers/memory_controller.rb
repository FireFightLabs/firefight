# What the workspace remembers and the instructions people give Halon, where people review, correct and write them.
class MemoryController < InertiaController
  authorizes Ability::Action::RESOURCE_MEMORY,
    read: %i[index],
    create: %i[create_memory],
    update: %i[confirm_memory correct_memory reject_memory destroy_memory]
  authorizes Ability::Action::RESOURCE_CATALOG, update: %i[create_instruction update_instruction destroy_instruction]

  TAB_QUERY = "tab"
  TAB_MEMORIES = "memories"
  TAB_INSTRUCTIONS = "instructions"
  CHANGED_FIRST = "Someone changed these instructions first. Their version is shown now."

  before_action :require_agent!

  def index
    memories = self.memories.includes(:subject, :source, :added_by, :confirmed_by, :rejected_by).order(updated_at: :desc)

    render inertia: "memory/index", props: {
      memories: ChatMemorySerializer.many(memories),
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

  def confirm_memory
    memory = memories.find(params[:id])
    return redirect_to(memory_path, alert: memory.confirm_blocked_reason) unless memory.confirm!(by: current_membership)

    redirect_to memory_path, notice: "Confirmed. Halon now reads it as confirmed by you."
  end

  def correct_memory
    memory = memories.find(params[:id])
    replacement = memory.reject!(by: current_membership, reason: params[:reason].to_s.strip, correction: params[:text].to_s.strip)
    return redirect_to(memory_path, alert: memory.reject_blocked_reason) unless replacement

    redirect_to memory_path, notice: "Corrected. Halon keeps the old wording as rejected so it does not learn it again."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to memory_path, alert: error.record.errors.full_messages.to_sentence
  end

  def reject_memory
    memory = memories.find(params[:id])
    return redirect_to(memory_path, alert: memory.reject_blocked_reason) unless memory.reject!(by: current_membership, reason: params[:reason].to_s.strip)

    redirect_to memory_path, notice: "Rejected. Halon stops using it and does not learn it again."
  end

  def destroy_memory
    memory = memories.find(params[:id])
    memory.destroy!

    redirect_to memory_path, notice: "Deleted. #{memory.delete_consequence}"
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

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    redirect_to dashboard_path, alert: Investigation.unavailable_reason(current_workspace)
  end

  def instructions_page = memory_path(TAB_QUERY => TAB_INSTRUCTIONS)

  # A memory about a resource outside the person's map reach is not on their page, and deciding on one finds nothing.
  def memories = Chat::Memory.visible_to(current_membership, current_workspace)

  # Instructions follow the same reach, so editing or removing one about a hidden resource finds nothing.
  def instructions = Chat::Instruction.visible_to(current_membership, current_workspace)

  def subject_param = Chat::Memory.subject_for_key(current_workspace, params[:subject], principal: current_membership)
end
