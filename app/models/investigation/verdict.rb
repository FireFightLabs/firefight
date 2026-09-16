# What one person said about a finding. The tally is the signal, not any single vote.
class Investigation::Verdict < ApplicationRecord
  belongs_to :finding, class_name: "Investigation::Finding"
  belongs_to :member, class_name: "WorkspaceMembership"

  validates :outcome, inclusion: { in: Investigation::Finding::OUTCOMES }
end
