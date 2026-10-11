# A member an admin took asking Halon away from, as the Permissions screen does it. A grant of investigations.create
# replaces the default and reaches nothing once it lapses. A grant cannot be written already expired, so it lapses here.
module HalonAccessHelper
  def take_halon_from(workspace, member)
    grant = Ability::Grant.grant!(workspace: workspace, principal: member, expires_at: 1.day.from_now,
                                  target: { action: Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE) })
    grant.update_column(:expires_at, 1.minute.ago)
  end

  # A turn the reply job runs ends the way a real one does, its answer saved in the chat and nothing owed. The block, when
  # given, does more first, such as pausing on a confirmation instead. Returns who each turn ran as, in order.
  def halon_replies(text = nil, &before)
    asked_as = []
    turn = Object.new
    turn.define_singleton_method(:run) do
      conversation = asked_as.last.first
      before ? before.call(conversation) : conversation.note!(text)
      conversation.reply_delivered!
    end
    Conversation::Runner.stubs(:new).with { |conversation, asker:| asked_as << [ conversation, asker ] }.returns(turn)
    asked_as
  end
end
