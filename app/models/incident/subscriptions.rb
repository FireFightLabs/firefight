class Incident
  module Subscriptions
    extend ActiveSupport::Concern

    included do
      has_many :incident_subscriptions, dependent: :destroy
      has_many :subscribers, through: :incident_subscriptions, source: :workspace_membership
    end

    def subscribed?(member)
      incident_subscriptions.exists?(workspace_membership: member)
    end

    # Both are idempotent, so a double click or a retried request changes
    # nothing the first one did not. The unique index settles a race between
    # two clicks that both saw no subscription.
    def subscribe!(member)
      incident_subscriptions.find_or_create_by!(workspace_membership: member) do |subscription|
        subscription.workspace = workspace
      end
    rescue ActiveRecord::RecordNotUnique
      incident_subscriptions.find_by!(workspace_membership: member)
    end

    def unsubscribe!(member)
      incident_subscriptions.where(workspace_membership: member).destroy_all
    end

    # One shared announcement message cannot show each reader their own state, so the
    # button toggles. Returns whether the member is subscribed afterwards.
    def toggle_subscription!(member)
      if subscribed?(member)
        unsubscribe!(member)
        false
      else
        subscribe!(member)
        true
      end
    end

    def subscriber_platform_user_ids
      subscribers.pluck(:platform_user_id)
    end
  end
end
