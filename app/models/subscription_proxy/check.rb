module SubscriptionProxy
  # How the subscription proxy was found when last checked, one row for the whole install. It fails when the proxy
  # does not answer, and when its settings would let one workspace's call reach another workspace's subscription, since
  # Firefight then sends it nothing.
  class Check < ApplicationRecord
    self.table_name = "subscription_proxy_checks"

    KEY = "proxy".freeze
    REASON_LIMIT = 500

    def self.current = find_by(key: KEY)

    def self.passing?
      check = current
      check.present? && check.checked_at.present? && check.failing_since.nil?
    end

    def self.passed!(version:)
      now = Time.current
      upsert({ key: KEY, checked_at: now, failing_since: nil, last_error: nil, version: version.presence, updated_at: now, created_at: now },
             unique_by: :key)
    end

    # Keeps the time it first failed, so the console says how long it has been down.
    def self.failed!(reason)
      now = Time.current
      insert({ key: KEY, checked_at: now, failing_since: now, last_error: reason.to_s.truncate(REASON_LIMIT), updated_at: now, created_at: now },
             unique_by: :key)
      where(key: KEY).update_all(checked_at: now, last_error: reason.to_s.truncate(REASON_LIMIT), updated_at: now)
      where(key: KEY, failing_since: nil).update_all(failing_since: now)
    end
  end
end
