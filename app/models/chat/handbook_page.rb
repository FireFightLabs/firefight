# One page of the workspace's handbook says how the workspace works on one subject. People write it, a repository or a
# connected tool syncs it, or it says who directs Halon in an incident. Its words are the page's current wording,
# a Chat::Instruction, and each edit keeps the earlier one as history. Halon reads short pages whole at the start of
# every chat and run, and searches long ones (Chat::HandbookPage::Reading).
class Chat::HandbookPage < ApplicationRecord
  include Positioned
  include ProviderDocPage::Chunking
  include Chat::HandbookPage::Reading

  self.table_name = "chat_handbook_pages"

  KIND_WRITTEN = "written".freeze
  KIND_DIRECTING = "directing".freeze
  KIND_SYNCED = "synced".freeze
  KINDS = [ KIND_WRITTEN, KIND_DIRECTING, KIND_SYNCED ].freeze

  TITLE_LIMIT = 120
  # A page is a document, not a note, so it holds what a team would write down, a long release guide included.
  TEXT_LIMIT = 200_000
  # The query string the Handbook page opens one page by, as a link Halon cites names it.
  PAGE_QUERY = "page".freeze

  # freezes opens the page with a freeze window to fill in.
  Suggestion = Data.define(:title, :hint, :example, :kind, :freezes) do
    def initialize(title:, hint:, example:, kind:, freezes: false) = super
  end

  DIRECTING_TITLE = "Who directs Halon in an incident".freeze

  # What Draft with Halon asks, as the person's first message in the chat it starts.
  DRAFT_REQUEST = "Draft our handbook. Read the resource map, our repositories and their CI, and our past incidents and " \
                  "postmortems. Then propose a handbook page for each thing a new teammate would need to know here, such as " \
                  "how we release, who owns what, what production is and when changes are frozen. Propose each page with " \
                  "propose_handbook_edit, cite what you read, and leave out anything the handbook already says.".freeze

  # Offered on an empty handbook as pages to start from.
  SUGGESTIONS = [
    Suggestion.new(title: "How we release", kind: KIND_WRITTEN,
                   hint: "The tools and steps a release goes through, and when a release counts as done.",
                   example: "Tag main, then run the release pipeline. A release is done once the checkout health check passes."),
    Suggestion.new(title: "Who owns what", kind: KIND_WRITTEN,
                   hint: "Which team or person answers for each service, and whom to page.",
                   example: "Payments owns checkout and billing. Page the platform team for anything in the cluster."),
    Suggestion.new(title: "What production is", kind: KIND_WRITTEN,
                   hint: "Which environments, databases and accounts are production, and which are safe to test in.",
                   example: "Production is the prod project and the main database. Staging is safe to break."),
    Suggestion.new(title: "Freeze windows", kind: KIND_WRITTEN, freezes: true,
                   hint: "When nothing may be released or changed, and who may lift a freeze. Halon's plans never run inside one.",
                   example: "Hotfixes for an open incident still go out during a freeze, with the incident lead's approval."),
    Suggestion.new(title: "On call", kind: KIND_WRITTEN,
                   hint: "Who is on call for what, whom Halon pages when an alert fires at night, and what it may change on its own.",
                   example: "Page the platform on-call for anything in the cluster, with the evidence. Halon may restart web when " \
                            "errors pass 5% and must wake a person for anything else, such as a rollback or a database change."),
    Suggestion.new(title: DIRECTING_TITLE, kind: KIND_DIRECTING,
                   hint: "Halon takes direction from whoever holds this role. When people in an incident ask for things that conflict, Halon says so and follows them.",
                   example: "During a release incident the release manager decides on rollbacks."),
    Suggestion.new(title: "Anything else", kind: KIND_WRITTEN,
                   hint: "Anything Halon should follow in every chat and investigation.",
                   example: "Never restart the primary database. Page the data team instead.")
  ].freeze

  belongs_to :workspace
  belongs_to :source, class_name: "Chat::HandbookSource", optional: true
  # Every wording the page has had, the current one last. Gone with the page.
  has_many :wordings, -> { order(:created_at) }, class_name: "Chat::Instruction", foreign_key: :handbook_page_id, inverse_of: :handbook_page,
                                                 dependent: :delete_all
  has_one :current_wording, -> { where(superseded_at: nil) }, class_name: "Chat::Instruction", foreign_key: :handbook_page_id, inverse_of: :handbook_page
  has_many :chunks, -> { order(:position) }, class_name: "Chat::HandbookChunk", foreign_key: :handbook_page_id, inverse_of: :page, dependent: :delete_all
  has_many :proposals, class_name: "Chat::HandbookProposal", foreign_key: :handbook_page_id, inverse_of: :handbook_page, dependent: :delete_all

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :title, uniqueness: { scope: :workspace_id, case_sensitive: false, message: "is already the title of another page" }
  validates :kind, inclusion: { in: KINDS }
  validate :one_directing_page, on: :create

  normalizes :title, with: ->(value) { value.to_s.squish }

  scope :ordered, -> { order(:position) }

  # The role whose holder Halon takes direction from in an incident. It is the one the handbook names while that role is
  # in use, else the Incident Lead.
  def self.directing_role(workspace)
    page = where(workspace: workspace, kind: KIND_DIRECTING).first
    page&.current_wording&.directing_role || lead_role(workspace)
  end

  def self.lead_role(workspace) = workspace.incident_roles.incident_lead.active.first

  def self.suggestion(title) = SUGGESTIONS.find { |each| each.title.casecmp?(title.to_s.squish) }

  # A new page with its first wording, last in the handbook. Who directs Halon names its role.
  def self.create_written!(workspace, title:, text:, by:, kind: KIND_WRITTEN, incident_role: nil, freeze_windows: [], source: nil, source_path: nil,
                           source_url: nil)
    transaction do
      page = new(workspace: workspace, title: title, kind: kind, source: source, source_path: source_path, source_url: source_url)
      page.save_in_position!
      Chat::Instruction.create!(workspace: workspace, handbook_page: page, text: text, incident_role: incident_role, freeze_windows: freeze_windows,
                                added_by: by)
      page.reload
    end
  end

  def directing? = kind == KIND_DIRECTING

  def synced? = kind == KIND_SYNCED

  def text = current_wording&.text.to_s

  def freeze_rules = current_wording&.freeze_rules || []

  # What chunking reads.
  def content = text

  def edit_blocked_reason
    "#{title} is synced from #{source&.label || 'its source'}. Change it there, or stop syncing it." if synced?
  end

  def delete_blocked_reason = edit_blocked_reason

  # Halon proposes changes to what people write, never to a synced page or to who directs it.
  def proposal_blocked_reason
    return edit_blocked_reason if synced?

    "Who directs Halon is a role people choose, so Halon does not propose changes to it." if directing?
  end

  # A new wording, and a new title when given, keeping the one the editor saw as history. wording_id is that one, so an
  # edit made over someone else's is refused rather than written over it. Nil when the page changed first.
  def write!(text:, by:, wording_id: current_wording&.id, title: nil, incident_role: current_wording&.incident_role,
             freeze_windows: current_wording&.freeze_windows || [])
    transaction do
      seen = wordings.find_by(id: wording_id, superseded_at: nil)
      next unless seen

      update!(title: title) if title.present? && title != self.title
      seen.revise!(text: text, by: by, incident_role: incident_role, freeze_windows: freeze_windows).tap { reset_wordings }
    end
  end

  # The wording just written is the current one from now on, for whoever holds this page.
  def reset_wordings
    association(:current_wording).reset
    association(:wordings).reset
  end

  # Where a person opens the page, as Halon cites it, at one of its headings when given.
  def url(heading: nil)
    anchor = section_anchors[heading.to_s] if heading.present?
    AppUrl.absolute(Rails.application.routes.url_helpers.settings_handbook_path(PAGE_QUERY => id, anchor: anchor))
  end

  # Each heading of the page and the anchor the Handbook page gives it, so a link Halon cites opens at that section.
  def section_anchors
    @section_anchors ||= sections.each_with_object({}) do |(path, _text), anchors|
      heading = path.split(ProviderDocPage::Chunking::PATH_JOIN).drop(1).last
      next if heading.blank? || anchors.key?(heading)

      base = heading.parameterize.presence || "section"
      taken = anchors.values
      anchors[heading] = taken.include?(base) ? (2..).lazy.map { |number| "#{base}-#{number}" }.find { |candidate| taken.exclude?(candidate) } : base
    end
  end

  def reload(...)
    @section_anchors = nil
    super
  end

  # The page's words split into sections again, keeping the vector of every section whose words did not change. The
  # words are indexed without their positions, since the page's text is encrypted (see the chunks table).
  def rechunk!
    kept = chunks.where.not(embedding: nil).to_h { |chunk| [ chunk.content_digest, chunk ] }
    rows = pieces.each_with_index.map do |piece, position|
      previous = kept[piece.digest]
      { piece: piece, position: position, embedding: previous&.embedding, embedding_model: previous&.embedding_model,
        embedded_digest: previous&.embedded_digest }
    end
    transaction do
      chunks.delete_all
      rows.each do |row|
        piece = row[:piece]
        Chat::HandbookChunk.create!(workspace_id: workspace_id, handbook_page_id: id, position: row[:position], heading_path: piece.heading_path,
                                    text: piece.text, content_digest: piece.digest, embedding: row[:embedding],
                                    embedding_model: row[:embedding_model], embedded_digest: row[:embedded_digest])
      end
    end
    rows.size
  end

  private

  def one_directing_page
    return unless directing? && self.class.where(workspace_id: workspace_id, kind: KIND_DIRECTING).exists?

    errors.add(:base, "The handbook already has a page saying who directs Halon. Edit that one instead.")
  end
end
