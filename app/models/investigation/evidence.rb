# One claim a finding makes, and what it rests on. Never a sentence on its own, so every line of
# an answer can be checked against what the agent actually looked at.
class Investigation::Evidence < ApplicationRecord
  self.table_name = "investigation_evidence"

  # The agent is told why, in words it can act on, and nothing is written.
  class Refused < StandardError; end

  belongs_to :finding, class_name: "Investigation::Finding"
  has_many :citations, -> { order(:created_at, :id) }, class_name: "Investigation::Citation",
           as: :cited_by, dependent: :destroy, inverse_of: :cited_by

  validates :claim, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(:position) }

  # What the claim rests on, in the words a step was given when it ran.
  def source_labels = citations.filter_map { |citation| citation.source.try(:label) }.uniq
end
