# One version of what a workflow does: its trigger, its steps, the edges between them, each step's config and the
# outputs it hands back to a workflow that ran it. Numbered in order, with who made it, why, and which version it came
# from. A draft changes one guarded edit at a time and counts each in revision. Publishing makes it live and retires the
# version that was. A published version never changes again, and restoring an old one makes a new draft from it.
class Workflow::Version < ApplicationRecord
  include Workflow::Version::References
  include Workflow::Version::Publishing
  include Workflow::Version::Drafting
  include Workflow::Version::Steps
  include Workflow::PrivateInputs
  include Workflow::Version::History
  include Workflow::Version::Pins
  include Workflow::Version::Trying

  self.table_name = "workflow_versions"

  STATUS_DRAFT = "draft".freeze
  STATUS_LIVE = "live".freeze
  # Was live, until a later version was published.
  STATUS_RETIRED = "retired".freeze
  # A draft someone threw away.
  STATUS_DISCARDED = "discarded".freeze
  STATUSES = [ STATUS_DRAFT, STATUS_LIVE, STATUS_RETIRED, STATUS_DISCARDED ].freeze
  CONTENT = %w[trigger steps edges outputs].freeze

  belongs_to :workflow, inverse_of: :versions
  belongs_to :author, class_name: "WorkspaceMembership", optional: true
  belongs_to :published_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :parent_version, class_name: "Workflow::Version", optional: true
  has_many :edits, class_name: "Workflow::Edit", foreign_key: :version_id, inverse_of: :version

  validates :number, presence: true, uniqueness: { scope: :workflow_id }
  validates :status, inclusion: { in: STATUSES }
  validates :author_kind, inclusion: { in: Workflow::AUTHOR_KINDS }
  before_validation :seal_private_inputs
  validate :content_well_formed
  validate :published_content_unchanged, on: :update

  scope :newest_first, -> { order(number: :desc) }

  def draft? = status == STATUS_DRAFT
  def live? = status == STATUS_LIVE
  def by_halon? = author_kind == Workflow::AUTHOR_HALON

  # What a run keeps and the engine runs, so later edits never reach a run already going.
  def snapshot = { "trigger" => trigger, "steps" => steps, "edges" => edges, "outputs" => outputs }.deep_dup

  # Every step, inside each for each too, by its id.
  def steps_by_id = Workflow::Version.steps_by_id_in(steps)

  def self.steps_by_id_in(steps) = all_steps(steps).index_by { |step| step["id"] }

  # Each step with the for each it sits inside, nil at the top, as the canvas draws them in one picture.
  Placed = Data.define(:step, :within)

  def placed_steps = Workflow::Version.placed(steps, nil).map { |step, within| Placed.new(step: step, within: within) }

  # Every connection, inside each for each too, with the for each it is inside.
  def placed_edges = Workflow::Version.placed_edges_of(steps, edges, nil)

  def self.placed(steps, within)
    Array(steps).flat_map do |step|
      inside = step["kind"] == DefinedWorkflow::KIND_FOR_EACH ? placed(step.to_h.dig("config", "steps"), step["id"]) : []
      [ [ step, within ], *inside ]
    end
  end

  def self.placed_edges_of(steps, edges, within)
    own = Array(edges).map { |edge| edge.merge("within" => within) }
    own + Array(steps).select { |step| step["kind"] == DefinedWorkflow::KIND_FOR_EACH }.flat_map do |step|
      placed_edges_of(step.dig("config", "steps"), step.dig("config", "edges"), step["id"])
    end
  end

  def self.all_steps(steps)
    Array(steps).flat_map do |step|
      inside = step["kind"] == DefinedWorkflow::KIND_FOR_EACH ? all_steps(step.to_h.dig("config", "steps")) : []
      [ step, *inside ]
    end
  end

  # Each problem that stops it being published, as a sentence.
  def problems
    found = Workflow::Trigger.problems(trigger)
    found.concat(DefinedWorkflow.problems(snapshot))
    found.concat(step_problems)
    found.concat(check_problems)
    found.concat(reference_problems)
    ids = Workflow::Version.all_steps(steps).map { |step| step["id"] }
    found << "Step ids must be unique across the whole workflow." unless ids.uniq.size == ids.size
    found.uniq
  end

  # Why content cannot be kept at all, whether saved whole or changed by an edit, as a sentence, or nil. A step that needs
  # a credential names a connection, so a value that looks like one is never kept.
  def self.content_problem(document)
    document = document.to_h.stringify_keys
    return "The trigger must be settings." unless document["trigger"].is_a?(Hash)
    return "The steps must be a list of steps." unless document["steps"].is_a?(Array) && document["steps"].all? { |step| step.is_a?(Hash) }
    return "The connections must be a list." unless document["edges"].is_a?(Array) && document["edges"].all? { |edge| edge.is_a?(Hash) }
    return "The outputs must be named values." unless document["outputs"].is_a?(Hash)

    secret_problem(document.slice(*CONTENT))
  end

  def self.secret_problem(value)
    text = value.to_json
    found = Chat::SecretFree::SECRET_PATTERNS.keys.find { |name| text.match?(Chat::SecretFree::SECRET_PATTERNS[name]) }
    "It looks like it holds a secret (#{found.to_s.humanize(capitalize: false)}), so it is not saved. Name the connection that holds it instead." if found
  end

  private

  # A private input's value never stays in the trigger, whoever wrote it there. It is kept with this version, so it is
  # saved only when the version is.
  def seal_private_inputs
    return unless trigger.is_a?(Hash)

    stripped, values = Workflow::Trigger.sealed(trigger)
    return if values.empty?

    self.trigger = stripped
    self.private_inputs = private_inputs_with(values)
  end

  def content_well_formed
    problem = self.class.content_problem(snapshot)
    errors.add(:base, problem) if problem
  end

  def published_content_unchanged
    return if status_was == STATUS_DRAFT
    return unless CONTENT.any? { |column| attribute_changed?(column) }

    errors.add(:base, "A published version never changes, so change its draft instead.")
  end
end
