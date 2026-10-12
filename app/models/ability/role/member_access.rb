# Who among the members can read or change through a connection's packs, as Who can do what chooses it: everyone, nobody
# or chosen people. Everyone is the pack's every_member flag, so a member who joins later has it too. A read pack held by
# every member is the default a member reads by (WorkspaceMembership#default_read?), and a changes pack held by every member
# reaches each of them as an unscoped grant would (Ability::Resolver). Chosen people are ordinary grants of the pack, the
# same rows the Permissions screen gives and revokes, so either place shows what the other did.
module Ability::Role::MemberAccess
  extend ActiveSupport::Concern

  EVERYONE = "everyone".freeze
  NOBODY = "nobody".freeze
  CHOSEN = "chosen".freeze
  CHOICES = [ EVERYONE, NOBODY, CHOSEN ].freeze
  # Beyond this many, a notice names the first few and counts the rest.
  NAMED_IN_NOTICE = 3

  # Where one pack stands for the members. people are those holding it by a grant when it is chosen people, and left_out
  # are members a No access or a lapsed grant keeps from a read every member otherwise has.
  Standing = Data.define(:role, :choice, :people_ids, :left_out_ids)
  # A connection's row: its read pack and its changes pack.
  Connection = Data.define(:integration, :read, :change)
  # Every connection's row, the members who can be chosen, and how many people the workspace has, admins included.
  Overview = Data.define(:connections, :members, :people_count)

  included do
    validate :every_member_only_on_connection_packs
  end

  class_methods do
    # Every connection's two rows, named as the Permissions screen names its packs, read from the grants as they stand now.
    def member_access_of(workspace)
      members = workspace.workspace_memberships.members.includes(:user).to_a.sort_by { |member| member.display_name.downcase }
      packs = workspace.ability_roles.where(pack: [ Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES ])
                       .joins(:integration).merge(Integration.where(deleted_at: nil))
                       .includes(:integration, :grants, :role_actions)
      connections = packs.group_by(&:integration).filter_map do |integration, pair|
        by_pack = pair.index_by(&:pack)
        read, change = by_pack.values_at(Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES)
        Connection.new(integration: integration, read: read.standing(members), change: change.standing(members)) if read && change
      end
      Overview.new(connections: connections.sort_by { |connection| connection.integration.display_name.downcase },
                   members: members, people_count: workspace.workspace_memberships.count)
    end

    # The packs every member of the workspace holds without a grant, of the kind given.
    def held_by_every_member(workspace_id, pack)
      where(workspace_id: workspace_id, pack: pack, every_member: true).where.not(integration_id: nil)
    end

    # Read packs every member does not read by default, so a member reads their tools only through a grant.
    def read_by_chosen_members(workspace_id)
      where(workspace_id: workspace_id, pack: Ability::Role::PACK_READ, every_member: false).where.not(integration_id: nil)
    end
  end

  def member_access_pack? = integration_id.present? && [ Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES ].include?(pack)

  # Whether every member's resolved grants depend on this pack, rather than only its holders'.
  def reaches_every_member? = member_access_pack? && (read_pack? ? !every_member? : every_member?)

  def standing(members)
    member_ids = members.map(&:id).to_set
    held = grants.select { |grant| grant.principal_type == WorkspaceMembership.name && member_ids.include?(grant.principal_id) }
    lapsed, live = held.partition { |grant| grant.no_access? || grant.expired? }
    return Standing.new(role: self, choice: EVERYONE, people_ids: [], left_out_ids: read_pack? ? lapsed.map(&:principal_id) : []) if every_member?

    Standing.new(role: self, choice: live.any? ? CHOSEN : NOBODY, people_ids: live.map(&:principal_id), left_out_ids: [])
  end

  # Why this pack cannot be set to the choice for these people, or nil.
  def member_access_blocked_reason(choice, people = [])
    return "Only a connection's read or changes pack is chosen for every member." unless member_access_pack?
    return "Choose Everyone, Nobody or the people who can #{member_verb} #{integration.display_name}." unless CHOICES.include?(choice)
    return empty_pack_reason if role_actions.empty?
    return unless choice == CHOSEN
    return "Pick at least one person, or choose Nobody." if people.empty?

    "Admins can always do everything, so pick members only." if people.any?(&:admin_access?)
  end

  # Why the dropdown is not offered at all, or nil.
  def member_access_unavailable_reason = (empty_pack_reason if member_access_pack? && role_actions.empty?)

  # Everyone holds it by the pack itself, and No access a member had on a read pack goes so they read again. Nobody and
  # chosen people take the pack off every member and leave it to grants, revoking the grants of anyone not chosen and
  # granting it in every environment to anyone chosen who does not already hold it live.
  def let_members!(choice, people: [], by: nil)
    blocked = member_access_blocked_reason(choice, people)
    raise ActiveRecord::RecordInvalid.new(tap { errors.add(:base, blocked) }) if blocked

    transaction do
      held = grants.where(principal_type: WorkspaceMembership.name, principal_id: workspace.workspace_memberships.members.select(:id)).to_a
      update!(every_member: choice == EVERYONE)
      case choice
      when EVERYONE
        held.select(&:no_access?).each(&:destroy!)
        settle_waiting_requests(by) if pack == Ability::Role::PACK_CHANGES
      when NOBODY
        held.each(&:destroy!)
      when CHOSEN
        choose!(held, people, by)
      end
    end
  end

  def member_access_notice(choice, people = [])
    name = integration.display_name
    case choice
    when EVERYONE then "Members can #{member_verb} #{name}."
    when NOBODY then "Members can no longer #{member_verb} #{name}."
    else "#{people_words(people)} can #{member_verb} #{name}."
    end
  end

  private

  def member_verb = read_pack? ? "read" : "change"

  def empty_pack_reason
    read_pack? ? "#{integration.display_name} has no tools that only read." : "#{integration.display_name} has no tools that change anything."
  end

  def choose!(held, people, by)
    chosen = people.map(&:id)
    held.reject { |grant| chosen.include?(grant.principal_id) }.each(&:destroy!)
    holding = held.reject { |grant| grant.no_access? || grant.expired? }.map(&:principal_id)
    people.reject { |person| holding.include?(person.id) }.each do |person|
      Ability::Grant.grant!(workspace: workspace, principal: person, target: { role: self }, granted_by: by)
    end
  end

  # Members who asked for this pack hold it now, so their requests are answered as a grant of it would answer them.
  def settle_waiting_requests(by)
    requests = Ability::PackRequest.waiting.where(role_id: id)
    settled = requests.pluck(:id)
    requests.update_all(given_at: Time.current, given_by_id: by&.id, updated_at: Time.current)
    settled.each { |request_id| PackRequestSettledJob.perform_later(request_id) }
  end

  def people_words(people)
    names = people.map(&:display_name)
    return names.to_sentence(two_words_connector: " and ", last_word_connector: " and ") if names.size <= NAMED_IN_NOTICE

    others = names.size - (NAMED_IN_NOTICE - 1)
    "#{names.first(NAMED_IN_NOTICE - 1).join(', ')} and #{others} others"
  end

  def every_member_only_on_connection_packs
    errors.add(:every_member, "applies only to a connection's read or changes pack") if every_member? && !member_access_pack?
  end
end
