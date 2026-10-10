# Something Halon looks at on a schedule the workspace sets, such as disks filling or certificates running out, to find
# a slow problem nobody asked about. Each time it is due it starts a run with the check as its subject, so one check never
# has two runs at once, and what the run finds is said through Investigation::Notice, once and again only when it worsens.
class Investigation::Check < ApplicationRecord
  include OptionGuards

  USAGE_NOUN = "run".freeze

  KIND_DISK = "disk".freeze
  KIND_CERTIFICATES = "certificates".freeze
  KIND_ERROR_BUDGET = "error_budget".freeze
  KIND_COST = "cost".freeze
  # Whatever the notes say to look at.
  KIND_CUSTOM = "custom".freeze
  KINDS = [ KIND_DISK, KIND_CERTIFICATES, KIND_ERROR_BUDGET, KIND_COST, KIND_CUSTOM ].freeze

  # What each kind looks at, as a person picks it, and the skill a run loads for it.
  Kind = Data.define(:key, :label, :description, :skill)
  KIND_DETAILS = {
    KIND_DISK => Kind.new(key: KIND_DISK, label: "Disk space",
                          description: "Disks, volumes and databases filling up, with the day each runs out at the current rate.",
                          skill: "disk_trends"),
    KIND_CERTIFICATES => Kind.new(key: KIND_CERTIFICATES, label: "Certificates",
                                  description: "TLS certificates on the domains you run that expire soon or will not renew.",
                                  skill: "certificate_expiry"),
    KIND_ERROR_BUDGET => Kind.new(key: KIND_ERROR_BUDGET, label: "Error budget",
                                  description: "Services spending their error budget faster than it lasts, with the day it runs out.",
                                  skill: "error_budget_burn"),
    KIND_COST => Kind.new(key: KIND_COST, label: "Cost",
                          description: "Spend from the billing your providers report, against the months before, with what grew.",
                          skill: "cost_trends"),
    KIND_CUSTOM => Kind.new(key: KIND_CUSTOM, label: "Something else",
                            description: "Whatever your notes describe, such as a queue that should never grow.", skill: nil)
  }.freeze

  CADENCE_DAILY = "daily".freeze
  CADENCE_WEEKLY = "weekly".freeze
  CADENCES = [ CADENCE_DAILY, CADENCE_WEEKLY ].freeze
  CADENCE_LABELS = { CADENCE_DAILY => "Every day", CADENCE_WEEKLY => "Every week" }.freeze

  NAME_LIMIT = 80
  NOTES_LIMIT = 2000

  NOT_DUE = "is not enabled, so Halon does not run it.".freeze
  ALREADY_RUNNING = "is already running. Halon says what it finds when it is done.".freeze

  belongs_to :workspace
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
  has_many :investigations, as: :subject, dependent: :restrict_with_exception
  has_many :notices, class_name: "Investigation::Notice", dependent: :nullify, inverse_of: :check

  # What people wrote about what matters here can name systems and thresholds, so it is kept like instructions are.
  encrypts :notes

  validates :name, presence: true, length: { maximum: NAME_LIMIT }
  validates :name, uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :cadence, inclusion: { in: CADENCES }
  validates :hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
  validates :weekday, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 6 }, if: :weekly?
  validates :notes, length: { maximum: NOTES_LIMIT }
  validate :known_time_zone
  validate :custom_says_what

  before_validation :normalize
  before_validation :schedule, if: -> { new_record? || will_save_change_to_cadence? || will_save_change_to_hour? || will_save_change_to_weekday? || will_save_change_to_time_zone? }

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:name) }
  scope :due, ->(now = Time.current) { active.where(next_run_at: ..now) }

  def self.usage_association = :investigations

  def self.kind_details(kind) = KIND_DETAILS.fetch(kind)

  def kind_details = self.class.kind_details(kind)

  def weekly? = cadence == CADENCE_WEEKLY

  def zone = ActiveSupport::TimeZone[time_zone]

  # The first time the schedule lands on after a moment, in the check's own time zone, so a daylight saving change
  # moves nothing a person set.
  def next_run_after(moment)
    local = moment.in_time_zone(zone)
    candidate = local.change(hour: hour, min: 0, sec: 0)
    if weekly?
      candidate += ((weekday - candidate.wday) % 7).days
      candidate += 7.days if candidate <= local
    elsif candidate <= local
      candidate += 1.day
    end
    candidate.change(hour: hour).utc
  end

  # Moves the schedule on as the sweep takes a due check, in one statement naming the time it was due at, so two sweeps
  # never both start it.
  def claim_due!(now = Time.current)
    following = next_run_after(now)
    taken = self.class.active.where(id: id, next_run_at: next_run_at).where(next_run_at: ..now)
                .update_all(next_run_at: following, last_run_at: now, updated_at: now) > 0
    reload if taken
    taken
  end

  # A person asked for it now. The schedule stays as it is.
  def run_now_blocked_reason
    return "#{name} #{NOT_DUE}" unless enabled?
    return "#{name} #{ALREADY_RUNNING}" if investigations.live.exists?

    Investigation.start_refusal(workspace)
  end

  # Turned back on, it runs next at its time, not at once for every time it missed.
  def enable!
    update!(deleted_at: nil, next_run_at: next_run_after(Time.current))
  end

  # A check that has run keeps its runs readable, so it is disabled rather than deleted.
  def deletion_blocked_reason
    return unless usage_count.positive?

    "Halon ran #{name} #{usage_count} #{'time'.pluralize(usage_count)}, and those runs stay readable. Disable it instead."
  end

  def last_run = investigations.seen.order(created_at: :desc).first

  def schedule_words
    at = format("%02d:00", hour)
    weekly? ? "Every #{Date::DAYNAMES[weekday]} at #{at} (#{time_zone})" : "Every day at #{at} (#{time_zone})"
  end

  private

  def normalize
    self.name = name.to_s.squish
    self.notes = notes.to_s.strip.presence
    self.weekday = nil unless weekly?
  end

  def schedule
    return unless zone && hour.present? && CADENCES.include?(cadence) && (!weekly? || weekday.present?)

    self.next_run_at = next_run_after(Time.current)
  end

  def known_time_zone
    errors.add(:time_zone, "is not a time zone Firefight knows") unless zone
  end

  def custom_says_what
    errors.add(:notes, "should say what Halon looks at") if kind == KIND_CUSTOM && notes.blank?
  end
end
