class AlertGroup < ApplicationRecord
  belongs_to :workspace
  belongs_to :incident
  has_many :alerts, dependent: :nullify

  validates :content_signature, presence: true
  validates :window_expires_at, presence: true

  scope :open_window, ->(now = Time.current) { where("window_expires_at > ?", now) }

  def self.signature_for(fields, content_match_fields)
    values = content_match_fields.map { |field| fields[field].to_s }
    Digest::SHA256.hexdigest(values.join("\n"))
  end
end
