# A workflow Halon made from a chat is shown there as a card, and in its thread when it has one, with what a person
# there can do with it: run it now, or cancel a one off before its time (turn a repeating one off). Whoever made it may
# cancel it, and so may anyone who may change a live workflow. The card ships each with why it cannot be pressed.
module Workflow::Chatting
  extend ActiveSupport::Concern

  ACTION_RUN_NOW = "run_now".freeze
  ACTION_CANCEL = "cancel".freeze
  ACTION_TURN_OFF = "turn_off".freeze
  CHAT_ACTIONS = [ ACTION_RUN_NOW, ACTION_CANCEL, ACTION_TURN_OFF ].freeze

  Offer = Data.define(:action, :blocked_reason)

  # What a person in the chat is offered, each with why they cannot press it, or nil.
  def chat_offers(member)
    offers = [ Offer.new(action: ACTION_RUN_NOW, blocked_reason: run_now_blocked_reason(member)) ]
    offers << Offer.new(action: stop_action, blocked_reason: stop_blocked_reason(member)) if live? && enabled? && !done?
    offers
  end

  # A one off is cancelled before its time, and one that repeats is turned off.
  def stop_action = one_off? ? ACTION_CANCEL : ACTION_TURN_OFF

  def run_now_blocked_reason(member)
    start_blocked_reason || ("#{member_words(member)} may not run workflows." unless may?(member, Ability::Action::ACTION_CREATE))
  end

  def stop_blocked_reason(member)
    return "#{name} is already off." unless enabled?
    return if member.is_a?(WorkspaceMembership) && member == created_by
    return if may?(member, Ability::Action::ACTION_UPDATE)

    "Only #{created_by&.display_name || 'whoever made it'} or a workspace admin can stop #{name}."
  end

  # The person who may change it, as the gateway answers.
  def may?(member, crud_action)
    member.respond_to?(:may?) && member.may?(Ability::Action::RESOURCE_WORKFLOWS, crud_action, workspace)
  end

  def chat_offer_blocked_reason(action, member)
    case action
    when ACTION_RUN_NOW then run_now_blocked_reason(member)
    when ACTION_CANCEL, ACTION_TURN_OFF then stop_blocked_reason(member)
    else "That is not something a workflow's card offers."
    end
  end

  private

  def member_words(member) = member.try(:display_name) || "Whoever is asking"
end
