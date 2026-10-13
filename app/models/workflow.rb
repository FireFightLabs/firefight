# Something a workspace runs again and again: a trigger and a graph of steps that read, judge, wait, ask and change.
# What it does is kept as versions. One is live, at most one draft is open, and people and Halon change the draft one
# attributed edit at a time. A run records the version it started on and runs from a snapshot of it, so editing never
# changes a run already going.
#
# A run acts as the workflow's own identity (agent), whoever started it, never as the person who pressed Run. Who may
# publish is the gateway's to answer, never a check here. A new workflow has no cost cap until someone sets one.
class Workflow < ApplicationRecord
  include NormalizedDescription
  include Workflow::Naming
  include Workflow::Editing
  include Workflow::FromLibrary
  include Workflow::Identity
  include Workflow::Scheduling
  include Workflow::Limits
  include Workflow::Chatting
  include Workflow::Showing

  AUTHOR_PERSON = "person".freeze
  AUTHOR_HALON = "halon".freeze
  # Firefight's library, for a version made from one of its items or moved on to a newer one.
  AUTHOR_FIREFIGHT = "firefight".freeze
  AUTHOR_KINDS = [ AUTHOR_PERSON, AUTHOR_HALON, AUTHOR_FIREFIGHT ].freeze
  NAME_LIMIT = 120

  # What a change step does when it lands in a freeze window: waits for the window to end, or stops the run.
  FREEZE_WAIT = "wait".freeze
  FREEZE_STOP = "stop".freeze
  FREEZE_BEHAVIOURS = [ FREEZE_WAIT, FREEZE_STOP ].freeze

  USAGE_NOUN = "time".freeze

  # Building, testing and running one, publishing one or changing it live, and granting its identity what it needs.
  CREATE_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE)
  PUBLISH_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE)
  GRANT_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE)
  READ_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_READ)

  belongs_to :workspace
  # The team on the catalog that owns it.
  belongs_to :owner_team, class_name: "CatalogEntry", optional: true
  # The machine principal its runs act as, nil until one is made for it.
  belongs_to :agent, optional: true
  belongs_to :live_version, class_name: "Workflow::Version", optional: true
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
  # The chat Halon made it from, where a step may post back to.
  belongs_to :origin_conversation, class_name: "Conversation", optional: true
  has_many :versions, class_name: "Workflow::Version", inverse_of: :workflow
  has_many :edits, class_name: "Workflow::Edit", inverse_of: :workflow
  has_many :runs, class_name: "Workflow::Run", inverse_of: :workflow
  # The open draft, for a list to load with the rest. Editing reads draft, which asks the database each time.
  has_one :draft_version, -> { where(status: Workflow::Version::STATUS_DRAFT) }, class_name: "Workflow::Version", inverse_of: false
  # Its newest run, loaded for a whole list in one query.
  has_one :latest_run, -> { select("DISTINCT ON (workflow_runs.workflow_id) workflow_runs.*").order("workflow_runs.workflow_id, workflow_runs.created_at DESC") },
          class_name: "Workflow::Run", inverse_of: false
  has_many :publish_requests, class_name: "Workflow::PublishRequest", dependent: :delete_all, inverse_of: :workflow

  validates :name, presence: true, length: { maximum: NAME_LIMIT }
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }, format: { with: /\A[a-z0-9_]+\z/ }
  validates :cost_cap_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :freeze_behaviour, inclusion: { in: FREEZE_BEHAVIOURS }
  validate :owner_is_a_team

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }
  # How many times each ran, counted in one subquery for a whole list.
  scope :with_run_counts, lambda {
    select("workflows.*", "(SELECT COUNT(*) FROM workflow_runs WHERE workflow_runs.workflow_id = workflows.id) AS run_count",
           "(SELECT COUNT(*) FROM workflow_runs WHERE workflow_runs.workflow_id = workflows.id AND NOT workflow_runs.test) AS real_run_count")
  }

  def draft = versions.find_by(status: Workflow::Version::STATUS_DRAFT)

  def live? = live_version_id.present?

  # Why a run cannot start now, as a sentence, or nil when it can.
  def start_blocked_reason
    return "Workflows are not switched on for this workspace." unless FeatureFlags.enabled?(workspace, FeatureFlags::WORKFLOWS)
    return "#{name} is switched off." unless enabled?
    return "#{name} has no published version to run." unless live_version

    nil
  end

  # How it stands as the Workflows page lists it.
  STATE_DRAFT = "draft".freeze
  STATE_LIVE = "live".freeze
  # Live, with a draft of changes waiting to be published.
  STATE_CHANGED = "changed".freeze
  STATE_OFF = "off".freeze
  STATE_DONE = "done".freeze
  STATES = [ STATE_DRAFT, STATE_LIVE, STATE_CHANGED, STATE_OFF, STATE_DONE ].freeze

  def state
    return STATE_DRAFT unless live?
    return STATE_DONE if done?
    return STATE_OFF unless enabled?

    draft_version ? STATE_CHANGED : STATE_LIVE
  end

  def waits_out_freezes? = freeze_behaviour == FREEZE_WAIT

  # The time zone its trigger keeps, which its times are said in.
  def time_zone = current_trigger[Workflow::Trigger::Schedule::KEY_TIME_ZONE].presence

  def trigger_words = Workflow::Trigger.words(current_trigger)

  # A workflow that runs once at a time, such as "in 30 minutes check X".
  def one_off? = current_trigger[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_ONCE_AT

  # The live version's trigger, or the draft's before anything was published.
  def current_trigger = (live_version || draft_version)&.trigger.to_h

  # A one off whose time came, which is listed with what is done and keeps its runs readable.
  # A test run is not its run, so a one off only tested and then turned off is not done.
  def done? = one_off? && live? && next_run_at.nil? && real_run_count.positive?

  def run_count = has_attribute?(:run_count) ? self[:run_count].to_i : runs.count

  def real_run_count = has_attribute?(:real_run_count) ? self[:real_run_count].to_i : runs.real.count

  # A workflow that ran keeps its runs readable, so it is turned off rather than deleted.
  def deletion_blocked_reason
    count = run_count
    return if count.zero?

    "#{name} ran #{count} #{USAGE_NOUN.pluralize(count)}, and those runs stay readable. Turn it off instead."
  end

  private

  def owner_is_a_team
    return if owner_team.nil?
    return errors.add(:owner_team, "must belong to this workspace") unless owner_team.workspace_id == workspace_id

    errors.add(:owner_team, "must be a team on the catalog") unless owner_team.catalog_type&.system_key == CatalogType::SYSTEM_KEY_TEAM
  end
end
