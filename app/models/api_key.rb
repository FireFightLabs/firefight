class ApiKey < ApplicationRecord
  TOKEN_PREFIX = "ff_"
  TOKEN_LENGTH = 36
  CACHE_TTL = 24.hours
  CACHE_PREFIX = "api_key/auth/"

  RESOURCES = %w[incidents severities statuses incident_types].freeze
  ACTIONS = %w[read create update delete].freeze

  belongs_to :workspace
  belongs_to :created_by, class_name: "WorkspaceMembership"

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true

  after_update :invalidate_cache!

  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :ordered, -> { order(created_at: :desc) }

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.base58(TOKEN_LENGTH)}"
  end

  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    digest = digest_token(raw_token)
    api_key = Rails.cache.fetch("#{CACHE_PREFIX}#{digest}", expires_in: CACHE_TTL) do
      find_by(token_digest: digest)
    end

    return nil unless api_key
    return nil unless api_key.active? && !api_key.deleted? && !api_key.expired?

    api_key
  end

  def self.create_with_token!(attributes)
    raw_token = generate_token
    api_key = create!(
      **attributes,
      token_digest: digest_token(raw_token),
      token_prefix: raw_token.first(12)
    )
    [ api_key, raw_token ]
  end

  def has_permission?(resource, action)
    resource_permissions = permissions[resource.to_s]
    return false unless resource_permissions.is_a?(Array)

    resource_permissions.include?(action.to_s)
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def invalidate_cache!
    Rails.cache.delete("#{CACHE_PREFIX}#{token_digest}")
  end
end
