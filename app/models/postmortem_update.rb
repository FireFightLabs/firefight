class PostmortemUpdate < ApplicationRecord
  GENERATED = "generated"
  EDITED = "edited"
  AI_EDITED = "ai_edited"

  UPDATE_TYPES = [ GENERATED, EDITED, AI_EDITED ].freeze

  include Recordable
  records Postmortem, recorder: :edited_by

  belongs_to :postmortem
  belongs_to :incident
  belongs_to :edited_by, class_name: "WorkspaceMembership"

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }
  validates :title, presence: true
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: ->(_) { Postmortem::STATUSES } }

  scope :ordered, -> { order(:created_at) }
end
