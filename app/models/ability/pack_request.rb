module Ability
  # A member refused a change asks the workspace admins for the pack that would allow it. One row per member and pack.
  # Asking is a click, never a refusal on its own, and the admins hear at most once a day for the same member and pack,
  # however often the button is pressed or the change refused.
  class PackRequest < ApplicationRecord
    WINDOW = 24.hours

    belongs_to :workspace
    belongs_to :requester, class_name: "WorkspaceMembership"
    belongs_to :role, class_name: "Ability::Role"
    belongs_to :given_by, class_name: "WorkspaceMembership", optional: true
    has_many :refusals, class_name: "Chat::PackRefusal", dependent: :destroy

    validates :role_id, uniqueness: { scope: :requester_id }
    validate :role_is_a_pack

    # Asked, and still waiting on an admin.
    scope :waiting, -> { where.not(requested_at: nil).where(given_at: nil, dismissed_at: nil) }

    def self.for!(requester, role)
      find_or_create_by!(workspace_id: requester.workspace_id, requester: requester, role: role)
    rescue ActiveRecord::RecordNotUnique
      find_by!(requester: requester, role: role)
    end

    # The pack a member is refused a change for, and the request that would ask for it, or nil when the principal is
    # not a member who could ask or the action has no pack.
    def self.for_refusal(principal, action)
      return unless principal.is_a?(WorkspaceMembership) && !principal.admin_access?

      pack = Ability::Role.to_ask_for(action)
      for!(principal, pack) if pack
    end

    # Claims the ask in one statement, so two clicks at once send one message. False when the admins were told within
    # the window and have not answered since.
    def claim_ask!
      won = self.class.where(id: id)
                .where("requested_at IS NULL OR requested_at < :since OR given_at IS NOT NULL OR dismissed_at IS NOT NULL", since: WINDOW.ago)
                .update_all(requested_at: Time.current, given_at: nil, given_by_id: nil, dismissed_at: nil, notifications: [], updated_at: Time.current)
      reload
      won == 1
    end

    # by is who would press Ask an admin. Only the person refused may.
    def ask_blocked_reason(by = requester)
      return "Only #{requester.display_name} can ask for this pack, since they were the one refused." unless by == requester
      return "#{requester.display_name} already has #{role.name}." if holds_pack?
      return unless waiting? && requested_at > WINDOW.ago

      "You asked the admins at #{requested_at.utc.strftime('%H:%M UTC')}, so they are not asked again until a day has passed."
    end

    def give_blocked_reason
      return "#{requester.display_name} already has #{role.name}." if holds_pack?

      "#{requester.display_name} no longer asks for this pack." if dismissed_at
    end

    # Granted through the same grant as the Permissions screen, in every environment and with no expiry. Marked given in
    # one statement, so the Slack button and the dashboard pressed at once grant it once.
    def give!(by:)
      transaction do
        self.class.where(id: id, given_at: nil).update_all(given_at: Time.current, given_by_id: by.id, updated_at: Time.current)
        Ability::Grant.grant!(workspace: workspace, principal: requester, target: { role: role })
      end
      reload
    end

    # True only for the press that dismissed it, so the member is told once.
    def dismiss!(by:)
      won = self.class.where(id: id, given_at: nil, dismissed_at: nil).update_all(dismissed_at: Time.current, given_by_id: by.id, updated_at: Time.current)
      reload
      won == 1
    end

    # Who answered, by name, or "An admin" when the pack was granted on the Permissions screen rather than from the request.
    def answered_by_name = given_by&.display_name || "An admin"

    def waiting? = requested_at.present? && given_at.nil? && dismissed_at.nil?

    def holds_pack? = workspace.ability_grants.where(principal: requester, role: role).reject(&:no_access?).any? { |grant| !grant.expired? }

    def add_notification!(channel_id:, message_id:)
      self.class.where(id: id).update_all([ "notifications = notifications || ?::jsonb", [ { channel_id: channel_id, message_id: message_id } ].to_json ])
    end

    # The people who can give a pack, by name, for a refusal to point at.
    def self.admins_of(workspace) = workspace.workspace_memberships.where(role: %i[admin owner]).includes(:user).order(:created_at)

    def self.admin_names(workspace) = admins_of(workspace).map(&:display_name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")

    # What a person refused a change is told. The pack, and who to ask in person.
    # "The workspace admin is Alice Smith." or "The workspace admins are Alice Smith and Dana Lee.", or nil without one.
    def self.admins_sentence(workspace)
      admins = admins_of(workspace).map(&:display_name)
      return if admins.empty?

      admins.one? ? "The workspace admin is #{admins.first}." : "The workspace admins are #{admins.to_sentence}."
    end

    def self.refusal_words(workspace, action_key, pack) = "You do not have permission to use #{action_key}. #{ask_words(workspace, pack)}"

    def self.ask_words(workspace, pack)
      admins = admin_names(workspace)
      admins.present? ? "Ask #{admins} for the #{pack.name} pack." : "A workspace admin can give you the #{pack.name} pack."
    end

    private

    def role_is_a_pack
      errors.add(:role, "must be a built-in pack") unless role&.built_in?
    end
  end
end
