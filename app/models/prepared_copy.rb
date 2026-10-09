# What preparing a repository's copy in the sandbox installed (its dependencies and the tool versions it asked for),
# kept so a later copy in any box of the same workspace starts with it rather than installing everything again. It is
# found by the repository and a key made of the files that decide what installing does (its lockfiles and version
# files), the repository's setup and the sandbox's own tools, so it is reused across commits until one of those
# changes. A workspace only ever reads its own, and one nobody used for KEPT_UNUSED_FOR is removed.
class PreparedCopy < ApplicationRecord
  KEPT_UNUSED_FOR = 7.days
  # Older keys of a repository, such as before its lockfile changed, are dropped once it has more than this many.
  KEPT_PER_REPOSITORY = 3
  # An archive larger than this is not kept, and the repository installs from nothing each time.
  MAX_BYTES = 2.gigabytes

  belongs_to :workspace
  has_one_attached :archive

  scope :unused, -> { where(last_used_at: ...KEPT_UNUSED_FOR.ago) }

  def self.key_for(lock_digest:, setup_digest:) = Digest::SHA256.hexdigest([ lock_digest, setup_digest.to_s ].join(":"))

  # The kept copy for this workspace, repository and key, or nil.
  def self.usable(workspace, repository, key) = where(workspace: workspace, repository: repository, install_key: key).joins(:archive_attachment).first

  # Kept from the file at path. A second worker keeping the same key at once keeps the first one's.
  def self.keep!(workspace, repository, key, path)
    kept = new(workspace: workspace, repository: repository, install_key: key, byte_size: File.size(path), last_used_at: Time.current)
    File.open(path, "rb") do |file|
      kept.archive.attach(io: file, filename: "prepared.tar.gz", content_type: "application/gzip", identify: false)
      kept.save!
    end
    where(workspace: workspace, repository: repository).where.not(id: kept.id).order(last_used_at: :desc).offset(KEPT_PER_REPOSITORY - 1).destroy_all
    kept
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def used! = self.class.where(id: id).update_all(last_used_at: Time.current)

  # Removes every kept copy nobody used for KEPT_UNUSED_FOR, with its archive.
  def self.sweep! = unused.find_each(&:destroy)
end
