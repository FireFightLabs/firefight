# Grouping knobs for the alert_routing domain live in domain_config. This is
# the single place that knows the keys and defaults, so ingest, serialization,
# and the settings writer can never disagree.
module Policy::AlertRoutingConfig
  extend ActiveSupport::Concern

  # Grouping defaults belong to the routing contract, not to AlertGroup, so
  # the policy engine never loads an alert model to validate a knob.
  DEFAULT_WINDOW_MINUTES = 10
  WINDOW_MINUTES_RANGE = (5..10_080).freeze # 5 minutes to 7 days
  DEFAULT_CONTENT_MATCH_FIELDS = [ "service" ].freeze

  included do
    validate :alert_routing_domain_config
  end

  def grouping_window_minutes
    minutes = domain_config["grouping_window_minutes"].presence || DEFAULT_WINDOW_MINUTES
    minutes.to_i
  end

  def content_match_fields
    Array(domain_config["content_match_fields"].presence || DEFAULT_CONTENT_MATCH_FIELDS)
  end

  # Partial-update semantics for the settings form: nil leaves a knob
  # untouched, an empty match_fields list reverts to the default.
  def domain_config_merging(window_minutes: nil, match_fields: nil)
    config = domain_config.dup
    config["grouping_window_minutes"] = window_minutes.to_i if window_minutes.present?

    unless match_fields.nil?
      cleaned = Array(match_fields).map { |field| field.to_s.strip }.reject(&:empty?)
      cleaned.empty? ? config.delete("content_match_fields") : config["content_match_fields"] = cleaned
    end

    config
  end

  private

  # Validated at write time so ingest never has to defend against nonsense
  # values.
  def alert_routing_domain_config
    return unless domain == Policy::DOMAIN_ALERT_ROUTING && domain_config.present?

    window = domain_config["grouping_window_minutes"]
    if window.present? && !WINDOW_MINUTES_RANGE.cover?(window.to_i)
      errors.add(:domain_config, "grouping window must be between 5 minutes and 7 days")
    end

    fields = domain_config["content_match_fields"]
    if fields.present? && (!fields.is_a?(Array) || fields.any? { |f| !f.is_a?(String) || f.strip.empty? })
      errors.add(:domain_config, "content match fields must be a list of field names")
    end
  end
end
