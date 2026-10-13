# Halon's suggestions on the canvas, accepted into the draft or dismissed, one at a time or all of one change at once.
# Each decision is guarded on the model, so two people deciding at once decide once.
class WorkflowSuggestionsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: %i[accept dismiss accept_all dismiss_all]

  def accept
    suggestion = suggestions.find(params[:suggestion_id])
    suggestion.accept!(by: current_membership)
    back_to_canvas(notice: "Halon's suggestion to #{suggestion.suggestion_words.downcase_first} was accepted.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  def dismiss
    suggestion = suggestions.find(params[:suggestion_id])
    suggestion.dismiss!(by: current_membership)
    back_to_canvas(notice: "Halon's suggestion to #{suggestion.suggestion_words.downcase_first} was dismissed.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  # Every suggestion waiting, or every one of a change when one is named, in the order Halon made them.
  def accept_all
    decided = workflow.accept_suggestions!(chosen, by: current_membership)
    back_to_canvas(notice: "#{decided_words(decided)} accepted.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  def dismiss_all
    decided = workflow.dismiss_suggestions!(chosen, by: current_membership)
    back_to_canvas(notice: "#{decided_words(decided)} dismissed.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  private

  def suggestions = workflow.proposals

  def chosen = params[:change_set_id].present? ? suggestions.where(change_set_id: params[:change_set_id]) : suggestions

  def decided_words(count) = count == 1 ? "Halon's suggestion was" : "#{count} of Halon's suggestions were"
end
