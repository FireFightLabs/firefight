class RunbookStep < ApplicationRecord
  # A tool is named as Halon calls it, which is a word of letters, numbers, underscores, dots and dashes.
  TOOL_NAME = /\A[A-Za-z0-9_.\-]+\z/

  belongs_to :runbook
  has_many :incident_actions, dependent: :nullify

  validates :title, presence: true
  validates :position, presence: true
  validates :tool, format: { with: TOOL_NAME, message: "must be a tool's name, such as run_history" }, allow_nil: true
  validate :arguments_well_formed

  before_validation :tidy_tool

  scope :ordered, -> { order(:position) }
  scope :active, -> { where(deleted_at: nil) }

  def deleted?
    deleted_at.present?
  end

  # Halon runs this step with its tool, rather than a responder doing it by hand.
  def tool? = tool.present?

  private

  def tidy_tool
    self.tool = tool.to_s.strip.presence
    self.arguments = {} if arguments.blank? || tool.nil?
  end

  def arguments_well_formed
    return errors.add(:arguments, "must be an object of the tool's arguments") unless arguments.is_a?(Hash)

    unknown = Runbook.placeholders_in(arguments) - runbook.input_keys
    errors.add(:arguments, "use #{unknown.map { |key| "{{#{key}}}" }.to_sentence}, which is not one of the runbook's inputs") if unknown.any?
  end
end
