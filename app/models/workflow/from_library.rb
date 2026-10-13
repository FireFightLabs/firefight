# A workflow made from one of Firefight's library items. It remembers the item, the version it holds and what that
# version said (library_base). One that follows the library (follows_library) moves with each new version while its
# steps are still Firefight's. A person may change its trigger, such as its schedule, and it keeps following, but once
# its steps are someone else's it is a copy. A copy is never changed under the workspace. It is told a newer version
# exists with what changed, and a person takes it into a draft or keeps their own (library_dismissed_version).
module Workflow::FromLibrary
  extend ActiveSupport::Concern

  # What a library version decides. The trigger is the workspace's to set.
  BODY = %w[steps edges outputs].freeze

  class_methods do
    # A new workflow holding the item as it is, as a draft that publishing makes live, as every new workflow is.
    def from_library!(item, workspace:, by:, name: item.name, following: true)
      blocked = from_library_blocked_reason(item) || name_taken_reason(workspace, name)
      raise Workflow::Edit::Refused, blocked if blocked

      transaction do
        workflow = create!(workspace: workspace, name: name, description: item.description, aliases: (name == item.name ? item.aliases : []),
                           created_by: by, library_key: item.key, library_version: item.version, library_base: item.definition,
                           follows_library: following)
        workflow.versions.create!(number: 1, status: Workflow::Version::STATUS_DRAFT, author_kind: Workflow::AUTHOR_FIREFIGHT,
                                  reason: "From Firefight's library, version #{item.version}.", **item.definition.symbolize_keys)
        workflow
      end
    end

    def body_of(content) = content.to_h.stringify_keys.slice(*BODY)

    # A workflow is found by its name and its other names, so a new one never takes a name another already answers to.
    def name_taken_reason(workspace, name)
      taken = named(where(workspace: workspace), name)
      "#{taken.name} already exists here, so give this one another name." if taken
    end

    # Why an item cannot be taken into the workspace, or nil.
    def from_library_blocked_reason(item)
      problem = item.problems.first
      "#{item.name} needs steps this version of Firefight cannot run yet. #{problem}" if problem
    end
  end

  def library_item = (Workflow::Library.find(library_key) if library_key.present?)

  def from_library? = library_key.present?

  # It follows the library while its steps are still the ones Firefight shipped.
  def following_library? = follows_library? && library_item.present? && !changed_from_library?

  def changed_from_library?
    current = live_version || draft
    current.present? && self.class.body_of(current.snapshot) != self.class.body_of(library_base)
  end

  # The library's newer version a copy has not been told about yet, or nil. A workflow that follows the library moves
  # with it instead.
  def library_update
    item = library_item
    return if item.nil? || following_library?
    return unless item.version > library_version.to_i && item.version > library_dismissed_version.to_i

    item
  end

  # Moves a workflow that follows the library on to the item's current version. It gets a new live version with Firefight's
  # steps and the workspace's own trigger, and a draft whose steps are still Firefight's moves along too. One that someone
  # changed since stops following and is told of the new version as a copy. Claimed on the version it held, so two
  # workers move it once.
  def upgrade_from_library!
    item = library_item
    return unless follows_library? && item && item.version > library_version.to_i
    return update_columns(follows_library: false, updated_at: Time.current) if changed_from_library?

    transaction do
      claimed = self.class.where(id: id, library_version: library_version)
                          .update_all(library_version: item.version, library_base: item.definition, updated_at: Time.current)
      raise ActiveRecord::Rollback unless claimed == 1

      publish_library_body!(item) if live_version
      move_draft_body!(item)
    end
    reload
  end

  # Opens a draft holding the library's newer version, with the workflow's own trigger, for a person to look at and
  # publish. The draft says who took it.
  def take_library!(by:)
    item = library_update
    raise Workflow::Edit::Refused, "There is no newer version of #{name} in Firefight's library to take." unless item
    raise Workflow::Edit::Refused, "Publish or discard the open draft first." if draft

    transaction do
      opened = open_draft!(by: by, reason: "Took Firefight's version #{item.version}.")
      moved = Workflow::Version.where(id: opened.id, status: Workflow::Version::STATUS_DRAFT, revision: opened.revision)
                               .update_all(**self.class.body_of(item.definition).symbolize_keys, revision: opened.revision + 1, updated_at: Time.current)
      raise Workflow::Edit::Refused, "Someone changed the draft since you looked, so look again." unless moved == 1

      update!(library_version: item.version, library_base: item.definition, library_dismissed_version: nil)
      opened.reload
    end
  end

  # Keeps the workspace's own steps, so it is told again only of a version newer than this one.
  def keep_own!
    item = library_update
    raise Workflow::Edit::Refused, "There is no newer version of #{name} in Firefight's library to keep yours over." unless item

    update!(library_dismissed_version: item.version)
  end

  private

  def publish_library_body!(item)
    before = live_version
    trigger = before.trigger.to_h["kind"] == item.trigger.to_h["kind"] ? before.trigger : item.trigger
    Workflow::Version.where(workflow_id: id, status: Workflow::Version::STATUS_LIVE).update_all(status: Workflow::Version::STATUS_RETIRED, updated_at: Time.current)
    upgraded = versions.create!(
      number: (versions.maximum(:number) || 0) + 1, status: Workflow::Version::STATUS_LIVE, trigger: trigger, **self.class.body_of(item.definition).symbolize_keys,
      author_kind: Workflow::AUTHOR_FIREFIGHT, reason: "Firefight's library, version #{item.version}.", parent_version: before, published_at: Time.current
    )
    self.class.where(id: id).update_all(live_version_id: upgraded.id, updated_at: Time.current)
  end

  # A draft whose steps are still the library's, such as one where a person changed only the schedule, takes the new
  # steps too, so publishing it never takes the workflow back a version. library_base still holds the version it left.
  def move_draft_body!(item)
    open = draft
    return unless open && self.class.body_of(open.snapshot) == self.class.body_of(library_base)

    Workflow::Version.where(id: open.id, status: Workflow::Version::STATUS_DRAFT, revision: open.revision)
                     .update_all(**self.class.body_of(item.definition).symbolize_keys, revision: open.revision + 1, updated_at: Time.current)
  end
end
