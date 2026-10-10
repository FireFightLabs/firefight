# Where synced handbook pages come from. A file or folder in a repository on a connected code host is read again when its
# default branch moves, and a document in a connected tool is read again on a schedule. Each file or document is a page
# people read but change only at the source. Stopping the sync takes its pages away.
class Chat::HandbookSource < ApplicationRecord
  self.table_name = "chat_handbook_sources"

  KIND_REPOSITORY = "repository".freeze
  KIND_DOCUMENT = "document".freeze
  KINDS = [ KIND_REPOSITORY, KIND_DOCUMENT ].freeze

  # A folder brings in its text files, at most this many, each a page.
  MAX_FILES = 50
  TEXT_FILES = /\.(md|markdown|mdx|txt|rst|adoc)\z/i
  PATH_FORMAT = %r{\A[^/\0][^\0]*\z}

  belongs_to :workspace
  belongs_to :integration, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  has_many :pages, -> { order(:position) }, class_name: "Chat::HandbookPage", foreign_key: :source_id, inverse_of: :source, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :repository, :path, presence: true, if: :repository?
  validates :path, format: { with: PATH_FORMAT, message: "must be a path inside the repository, such as docs/ or HANDBOOK.md" }, allow_blank: true, if: :repository?
  validate :path_stays_inside, if: :repository?
  validates :reference, presence: true, if: :document?

  normalizes :path, with: ->(value) { value.to_s.strip.delete_prefix("/") }
  normalizes :reference, with: ->(value) { value.to_s.strip }

  def repository? = kind == KIND_REPOSITORY

  def document? = kind == KIND_DOCUMENT

  # A folder's path ends with a slash, or names no file Firefight reads as text.
  def folder? = repository? && (path.end_with?("/") || !path.match?(TEXT_FILES))

  # Such as "docs/ in acme/web" or "Release guide in Notion".
  def label
    return "#{path} in #{repository}" if repository?

    [ pages.first&.title || "a document", integration&.name ].compact.join(" in ")
  end

  # Whether a push to branch of repository moves what this source reads.
  def moved_by?(repository_name, branch_name)
    repository? && repository.casecmp?(repository_name.to_s) && (branch.blank? || branch == branch_name)
  end

  # Records a read that failed, keeping the pages as they were, or one that succeeded.
  def failed!(words) = update!(sync_error: words.to_s.truncate(500))

  # note says what a read that worked still left out, such as a file over the size cap.
  def synced!(digest:, branch: nil, url: nil, note: nil)
    update!(digest: digest, branch: branch || self.branch, url: url || self.url, synced_at: Time.current, sync_error: note)
  end

  private

  def path_stays_inside
    errors.add(:path, "must stay inside the repository") if path.to_s.split("/").include?("..")
  end
end
