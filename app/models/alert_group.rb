class AlertGroup < ApplicationRecord
  DEFAULT_WINDOW_MINUTES = 10
  WINDOW_MINUTES_RANGE = (5..10_080).freeze # 5 minutes to 7 days
  DEFAULT_CONTENT_MATCH_FIELDS = [ "service" ].freeze

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
