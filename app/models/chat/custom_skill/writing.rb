# How a skill gets a new version. A person's save, a restore and taking a newer library version each make a new live
# version and retire the one that was, in one update guarded on the version the writer saw, so two people saving at once
# never overwrite each other. Halon only proposes. Its version waits until a person accepts it, as written or edited
# first, or dismisses it.
module Chat::CustomSkill::Writing
  extend ActiveSupport::Concern

  # A change that cannot be made, with the sentence that says why.
  class Refused < StandardError; end

  CHANGED_FIRST = "Someone changed this skill since you opened it, so look at it again before saving.".freeze
  KEEPS_NAME = "Halon proposed a change to this skill, so it keeps its name.".freeze

  class_methods do
    # A new skill with its first version live.
    def create_with!(workspace:, name:, content:, by:, reason: nil, author_kind: Chat::CustomSkill::Version::AUTHOR_PERSON, **attributes)
      transaction do
        free_dormant_name!(workspace, name)
        skill = create!(workspace: workspace, name: name, created_by: by, **attributes)
        version = skill.versions.create!(number: 1, status: Chat::CustomSkill::Version::STATUS_LIVE, author_kind: author_kind,
                                         author: by, reason: reason, **Chat::CustomSkill::Version.content_attributes(content))
        skill.update!(live_version: version)
        skill
      end
    end

    # A skill only Halon ever proposed, and dismissed, gives its name up to the next one made.
    def free_dormant_name!(workspace, name)
      found = find_by(workspace: workspace, name: normalize_value_for(:name, name))
      found.destroy! if found&.dormant?
    end
  end

  # A new live version holding content, written on top of the version the writer saw (seen, the live one by default).
  def write!(content, by:, reason: nil, seen: live_version_id, name: self.name, author_kind: Chat::CustomSkill::Version::AUTHOR_PERSON, **attributes)
    renaming = self.class.normalize_value_for(:name, name) != self.name
    raise Refused, rename_blocked_reason if renaming && rename_blocked_reason

    transaction do
      retire!(seen)
      version = versions.create!(number: next_number, status: Chat::CustomSkill::Version::STATUS_LIVE, author_kind: author_kind,
                                 author: by, reason: reason, parent_version_id: seen, **Chat::CustomSkill::Version.content_attributes(content))
      update!(name: name, live_version: version, **attributes)
      version
    end
  end

  # Halon's proposed version, waiting on a person. A proposal for a new skill makes the skill with nothing live yet.
  def propose!(content, reason:, conversation: nil)
    versions.create!(number: next_number, status: Chat::CustomSkill::Version::STATUS_PROPOSED, author_kind: Chat::CustomSkill::Version::AUTHOR_HALON,
                     reason: reason, conversation: conversation, parent_version: live_version, **Chat::CustomSkill::Version.content_attributes(content))
  end

  # Why a proposal cannot be accepted as written, or nil. One made on a version someone has replaced since is out of date,
  # though a person can still edit it first, since then they wrote what goes live.
  def accept_blocked_reason(proposal)
    return "This proposal was already decided." unless proposal.proposed?
    return "This skill changed since Halon proposed this, so edit it first or dismiss it." if proposal.parent_version_id != live_version_id

    nil
  end

  # A change Halon proposed to a skill the workspace has keeps its name. A new skill takes the name the person gives it.
  def accept_rename_blocked_reason(proposal) = (KEEPS_NAME if proposal.parent_version_id)

  # Makes a proposal live, as Halon wrote it or as the person edited it (content). Claimed with one guarded update, so two
  # people accepting at once accept it once.
  def accept!(proposal, by:, content: nil, name: self.name)
    blocked = accept_blocked_reason(proposal)
    raise Refused, blocked if blocked && !(content && proposal.proposed?)

    renaming = self.class.normalize_value_for(:name, name) != self.name
    raise Refused, accept_rename_blocked_reason(proposal) if renaming && accept_rename_blocked_reason(proposal)

    transaction do
      if content
        claim!(proposal, Chat::CustomSkill::Version::STATUS_EDITED, by)
        write!(content, by: by, reason: "Edited Halon's proposal before accepting it. #{proposal.reason}".strip, name: name)
      else
        retire!(proposal.parent_version_id)
        claim!(proposal, Chat::CustomSkill::Version::STATUS_LIVE, by)
        update!(live_version: proposal)
      end
    end
    reload
  end

  # Drops a proposal. A skill that only ever existed as Halon's proposal stays out of sight, so Halon can still be told.
  def dismiss!(proposal, by:)
    claim!(proposal, Chat::CustomSkill::Version::STATUS_DISMISSED, by)
    reload
  end

  # Nothing live and nothing waiting, as when Halon's proposal for a new skill was dismissed. Its name is free again.
  def dormant? = live_version_id.nil? && !versions.proposed.exists?

  # A new live version holding an older one's content. History is never rewritten.
  def restore!(version, by:)
    raise Refused, "This is already the live version." if version.id == live_version_id
    raise Refused, "Only a version that was live can be restored." unless version.status.in?([ Chat::CustomSkill::Version::STATUS_RETIRED ])

    write!(version.content, by: by, reason: "Restored version #{version.number}.")
  end

  private

  def next_number = (versions.maximum(:number) || 0) + 1

  # Retires the live version the writer saw, refusing when it is no longer live.
  def retire!(seen)
    return if seen.nil? && live_version_id.nil?

    moved = Chat::CustomSkill::Version.where(id: seen, custom_skill_id: id, status: Chat::CustomSkill::Version::STATUS_LIVE)
                                      .update_all(status: Chat::CustomSkill::Version::STATUS_RETIRED, updated_at: Time.current)
    raise Refused, CHANGED_FIRST unless moved == 1 && seen == live_version_id
  end

  def claim!(proposal, status, by)
    moved = Chat::CustomSkill::Version.where(id: proposal.id, status: Chat::CustomSkill::Version::STATUS_PROPOSED)
                                      .update_all(status: status, decided_by_id: by&.id, decided_at: Time.current, updated_at: Time.current)
    raise Refused, "This proposal was already decided." unless moved == 1

    proposal.reload
  end
end
