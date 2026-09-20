# The wording behind a ledger row's prompt_version. Written once per wording, read when runs are compared.
class PromptVersion < ApplicationRecord
  validates :template, :version, :text, presence: true

  # Remembered per process as well, since every model call would otherwise ask for a row that rarely changes.
  def self.remember!(template:, version:, text:)
    return if template.blank? || version.blank? || text.blank?
    return if seen.include?([ template, version ])

    create!(template: template, version: version, text: text, first_seen_at: Time.current)
    seen << [ template, version ]
  rescue ActiveRecord::RecordNotUnique
    seen << [ template, version ]
  end

  def self.seen = @seen ||= Concurrent::Set.new
end
