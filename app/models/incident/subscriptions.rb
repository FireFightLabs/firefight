class Incident
  module Subscriptions
    extend ActiveSupport::Concern

    SUBSCRIBED = :subscribed
    ALREADY_SUBSCRIBED = :already_subscribed
    UNSUBSCRIBED = :unsubscribed

    included do
      has_many :incident_subscriptions, dependent: :destroy
      has_many :subscribers, through: :incident_subscriptions, source: :workspace_membership
    end

    def subscribed?(member)
      incident_subscriptions.exists?(workspace_membership: member)
    end

    # Says whether this call is the one that subscribed, so a second click is
    # answered honestly. The unique index settles a race between two clicks.
    def subscribe!(member)
      subscription = incident_subscriptions.find_or_create_by!(workspace_membership: member) do |row|
        row.workspace = workspace
      end
      subscription.previously_new_record? ? SUBSCRIBED : ALREADY_SUBSCRIBED
    rescue ActiveRecord::RecordNotUnique
      ALREADY_SUBSCRIBED
    end

    def unsubscribe!(member)
      incident_subscriptions.where(workspace_membership: member).destroy_all
      UNSUBSCRIBED
    end

    def subscription_notice(state)
      case state
      when SUBSCRIBED
        "You are subscribed to #{identifier}. Every update Firefight posts about it will reach you as a direct message."
      when ALREADY_SUBSCRIBED
        "You are already subscribed to #{identifier}."
      when UNSUBSCRIBED
        "You are no longer subscribed to #{identifier}."
      end
    end

    def subscriber_platform_user_ids
      subscribers.pluck(:platform_user_id)
    end
  end
end
