class Shoutout < ApplicationRecord
  belongs_to :incident
  belongs_to :from_member, class_name: "WorkspaceMembership"
  belongs_to :to_member, class_name: "WorkspaceMembership", optional: true

  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
