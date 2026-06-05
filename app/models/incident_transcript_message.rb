class IncidentTranscriptMessage < ApplicationRecord
  include Scrubbing

  belongs_to :workspace
  belongs_to :workspace_membership, optional: true
  belongs_to :incident

  validates :slack_ts, :slack_user_id, :posted_at, presence: true

  encrypts :content

  scope :kept, -> { where(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def self.grouped_for(incident, workspace:)
    rows = incident.incident_transcript_messages.kept.order(:posted_at).to_a
    return [] if rows.empty?

    members = workspace.workspace_memberships.index_by(&:platform_user_id)

    top_level = []
    threads = Hash.new { |h, k| h[k] = [] }

    rows.each do |row|
      formatted = {
        at: row.posted_at.iso8601(6),
        by: members[row.slack_user_id]&.user&.name || row.slack_user_id,
        text: row.content,
        ts: row.slack_ts
      }

      parent = row.slack_thread_ts
      if parent && parent != row.slack_ts
        threads[parent] << formatted
      else
        top_level << formatted
      end
    end

    top_level.map { |msg| threads[msg[:ts]].any? ? msg.merge(replies: threads[msg[:ts]]) : msg }
  end
end
