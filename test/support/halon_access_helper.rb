# A member an admin took asking Halon away from, as the Permissions screen does it. A grant of investigations.create
# replaces the default and reaches nothing once it lapses. A grant cannot be written already expired, so it lapses here.
module HalonAccessHelper
  def take_halon_from(workspace, member)
    grant = Ability::Grant.grant!(workspace: workspace, principal: member, expires_at: 1.day.from_now,
                                  target: { action: Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE) })
    grant.update_column(:expires_at, 1.minute.ago)
  end
end
