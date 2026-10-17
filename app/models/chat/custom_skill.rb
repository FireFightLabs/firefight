# A workspace's own skill: the same recipe as Firefight's in config/skills (when it is used, the tools it needs, numbered
# steps), kept as a record with every version it had and who wrote each. It is written from scratch, copied from
# Firefight's library, imported from a SKILL.md file, or proposed by Halon and accepted by a person. Halon loads it with
# use_skill like any other, and the tools it names are offered through the same catalog, so loading one never reaches a
# tool the person or the run could not already use.
#
# A copy keeps the library skill's name and is used in its place. It remembers the library version it came from, is told
# when Firefight ships a newer one with what changed, and is never changed under the workspace.
class Chat::CustomSkill < ApplicationRecord
  include Chat::CustomSkill::Usage
  include Chat::CustomSkill::Writing
  include Chat::CustomSkill::Library

  self.table_name = "chat_custom_skills"

  NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
  NAME_LIMIT = 64

  belongs_to :workspace
  belongs_to :live_version, class_name: "Chat::CustomSkill::Version", optional: true
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
  has_many :versions, class_name: "Chat::CustomSkill::Version", inverse_of: :custom_skill

  normalizes :name, with: ->(value) { value.to_s.strip.downcase.tr("- ", "__") }

  validates :name, presence: true, length: { maximum: NAME_LIMIT }
  validates :name, format: { with: NAME_FORMAT, message: "must be lowercase letters, numbers and underscores, starting with a letter" },
                   allow_blank: true
  validates :name, uniqueness: { scope: :workspace_id, message: "is taken by another of this workspace's skills" }
  validate :name_not_firefights

  scope :live, -> { where.not(live_version_id: nil) }
  scope :switched_on, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }

  # The skills Halon loads: live and switched on. A copy switched off leaves Firefight's skill of its name to be loaded.
  def self.definitions_for(workspace)
    where(workspace: workspace).live.switched_on.includes(:live_version).ordered.map(&:definition)
  end

  SWITCHED_OFF = "is switched off on the Skills page".freeze

  # The workspace's own skill of this name when it is switched off, which nothing may follow, or nil. A copy that is off
  # is not in the way, since Firefight's own skill of its name is followed instead.
  def self.switched_off(workspace, name)
    where(workspace: workspace, enabled: false, library_name: nil).live.find_by(name: normalize_value_for(:name, name))
  end

  def self.off_reason(workspace, name)
    off = switched_off(workspace, name)
    "#{off.name} #{SWITCHED_OFF}." if off
  end

  # Turns it on or off. Off, Halon no longer loads it and a workflow step that runs it is refused, until it is on again.
  def switch!(on:)
    update!(enabled: on)
  end

  def definition(version = live_version)
    Chat::Skill::Definition.new(
      name: name, source: source, domain: domain, used_when: version.used_when, tools: version.tools, steps: version.steps,
      references: version.references, signals: version.signals, version: version.number, custom_skill_id: id
    )
  end

  # Halon's proposal from a chat, for the workspace's skill of that name, a copy of Firefight's skill of that name, or a
  # new skill. The skill it would make or change stays as it is until a person decides.
  def self.propose_for!(workspace, name:, content:, reason:, conversation: nil)
    transaction do
      skill = find_by(workspace: workspace, name: normalize_value_for(:name, name)) || new_for(workspace, name)
      skill.save! if skill.new_record?
      skill.propose!(content, reason: reason, conversation: conversation)
    end
  end

  # An unsaved skill of that name, set up as the copy of Firefight's skill when it has one.
  def self.new_for(workspace, name)
    library = Chat::Skill.find(normalize_value_for(:name, name))
    return new(workspace: workspace, name: name) unless library

    new(workspace: workspace, name: library.name, source: library.source, domain: library.domain, library_name: library.name,
        library_version: library.version, library_base: library.content)
  end

  # Halon's proposals waiting on a person, oldest first.
  def proposals = versions.proposed.order(:created_at)

  private

  # A name of Firefight's own is taken, except by the copy of that skill, which is used in its place.
  def name_not_firefights
    return if name.blank? || name == library_name
    return unless Chat::Skill.find(name)

    errors.add(:name, "is the name of one of Firefight's skills, so copy that skill to change it, or pick another name")
  end
end
