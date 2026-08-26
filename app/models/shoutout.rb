class Shoutout < ApplicationRecord
  belongs_to :incident
  belongs_to :from_member, polymorphic: true
  belongs_to :to_member, polymorphic: true, optional: true

  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def to_context_hash
    { from: from_member.actor_display_name, to: to_member&.actor_display_name, message: }
  end
end
