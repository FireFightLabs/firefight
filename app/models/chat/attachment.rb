# A file a person gave Halon with a message, from the dashboard or a platform. The bytes sit in the object store
# encrypted with the app's own keys, and what Halon reads of a text file or a PDF is kept already redacted.
# An upload belongs to whoever sent it until it goes with a message, and then to that message's chat.
class Chat::Attachment < ApplicationRecord
  self.table_name = "chat_attachments"

  include Chat::Attachment::Reading

  KIND_IMAGE = "image"
  KIND_PDF = "pdf"
  KIND_TEXT = "text"
  # A file a platform shared that could not be taken, kept so Halon can say so rather than ignore it.
  KIND_UNREAD = "unread"
  KINDS = [ KIND_IMAGE, KIND_PDF, KIND_TEXT, KIND_UNREAD ].freeze

  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  PDF_TYPE = "application/pdf".freeze
  TEXT_TYPE = "text/plain".freeze
  TEXT_TYPES = %w[application/json application/xml application/x-yaml application/yaml application/x-sh application/sql
                  application/javascript application/x-ruby application/toml].freeze
  TEXT_EXTENSIONS = %w[
    log txt text out err csv tsv json jsonl ndjson yaml yml md markdown rst xml toml ini cfg conf properties env
    rb py js mjs cjs ts tsx jsx go java kt kts scala rs c h cc cpp hpp cs php swift m sh bash zsh fish ps1 sql graphql
    gql proto tf tfvars hcl html htm css scss sass less vue svelte lua pl r dart ex exs erl hs clj gradle diff patch
    dockerfile
  ].freeze
  TEXT_NAMES = %w[dockerfile makefile procfile gemfile rakefile jenkinsfile].freeze

  MAX_PER_MESSAGE = 4
  # Anthropic takes an image up to 5 MB, and a PDF the provider reads whole stays well inside every provider's request.
  MAX_BYTES = { KIND_IMAGE => 5.megabytes, KIND_PDF => 10.megabytes, KIND_TEXT => 5.megabytes }.freeze
  # Bedrock's Converse API takes smaller images and documents inline than the others.
  PROVIDER_MAX_BYTES = { "bedrock" => { KIND_IMAGE => 3.5.megabytes, KIND_PDF => 4.megabytes } }.freeze
  # A platform is told this before it downloads anything, since the kind is known only from the bytes.
  LARGEST = MAX_BYTES.values.max
  # Anthropic reads at most 100 pages of a PDF, so a longer one is read as text.
  PDF_PAGES = 100
  READ_TIMEOUT = 15.seconds
  # An upload nobody sent is let go after this.
  UNSENT_FOR = 1.day

  ACCEPTED = "Halon reads images (PNG, JPEG, GIF or WebP), PDFs, and text files such as logs, CSV, JSON, YAML, Markdown " \
             "and code.".freeze
  TOO_MANY = "Up to #{MAX_PER_MESSAGE} files can go with one message.".freeze
  IMAGES_UNREAD = "Halon's model is not known to read images, so it will say it could not look at this one.".freeze

  # The sentence says what was wrong and what is accepted.
  class Refused < StandardError; end

  # What a workspace's chats take, for the page to say before anything is sent.
  Rules = Data.define(:max_files, :max_bytes, :accept, :reads_images)

  belongs_to :workspace
  belongs_to :chat, optional: true
  belongs_to :message, class_name: "Chat::Message", foreign_key: :chat_message_id, optional: true, inverse_of: :attached_files
  belongs_to :queued_message, class_name: "Chat::QueuedMessage", optional: true, inverse_of: :attached_files
  belongs_to :uploaded_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :blob, class_name: "ActiveStorage::Blob", optional: true
  belongs_to :saved_result, class_name: "Chat::SavedResult", optional: true

  # The name is the person's own words, like the message it goes with.
  encrypts :filename
  encrypts :text

  validates :filename, :content_type, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Where it came among the files sent with one message, which is the order the person attached them in.
  scope :in_order, -> { order(:position, :created_at, :id) }
  scope :unsent, -> { where(chat_id: nil) }
  scope :abandoned, -> { unsent.where(created_at: ...UNSENT_FOR.ago) }

  after_destroy_commit :let_go_of_bytes

  def self.rules_for(workspace, model_id: nil)
    model_id ||= FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace).model
    Rules.new(
      max_files: MAX_PER_MESSAGE, max_bytes: limits_for(workspace).values.max, accept: accept_list,
      reads_images: FirefightAi.input_modalities(model_id).include?(KIND_IMAGE)
    )
  end

  def self.accept_list
    [ *IMAGE_TYPES, PDF_TYPE, *TEXT_EXTENSIONS.map { |extension| ".#{extension}" } ].join(",")
  end

  def self.limits_for(workspace)
    provider = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace).provider_name.to_s
    MAX_BYTES.merge(PROVIDER_MAX_BYTES.fetch(provider, {}))
  end

  # Raises Refused when the file is not one Halon reads, is empty or is too large for its kind.
  def self.take!(workspace:, uploaded_by:, filename:, bytes:)
    name = clean_name(filename)
    bytes = bytes.to_s.b
    raise Refused, "#{name} is empty." if bytes.empty?

    kind, content_type = detect(name, bytes)
    raise Refused, "#{name} is not a file Halon reads. #{ACCEPTED}" unless kind

    limit = limits_for(workspace).fetch(kind)
    raise Refused, too_large(name, bytes.bytesize, limit, kind) if bytes.bytesize > limit

    read = Chat::Attachment::Intake.read(kind, bytes, name)
    stored = store(bytes)
    create!(
      workspace: workspace, uploaded_by: uploaded_by, filename: name, content_type: content_type, byte_size: bytes.bytesize,
      kind: kind, blob: stored, text: read.text, redactions: read.redactions, page_count: read.page_count
    )
  rescue ActiveRecord::RecordInvalid
    stored&.purge
    raise
  end

  NOT_FOUND = "A file you attached is no longer there. Attach it again.".freeze

  # The uploads a person is sending with a message, which must be their own and not sent yet.
  def self.to_send!(workspace:, member:, ids:)
    ids = Array(ids).compact_blank.map(&:to_s).uniq
    return [] if ids.empty?
    raise Refused, TOO_MANY if ids.size > MAX_PER_MESSAGE

    files = workspace.chat_attachments.unsent.where(uploaded_by: member, id: ids).to_a
    raise Refused, NOT_FOUND unless files.size == ids.size

    # In the order they were attached, which uploads finishing at different speeds do not keep.
    files.sort_by { |file| ids.index(file.id) }
  end

  # A file a platform shared that Halon will not read, kept with why.
  def self.unread!(workspace:, uploaded_by:, filename:, byte_size:, refusal:)
    create!(
      workspace: workspace, uploaded_by: uploaded_by, filename: clean_name(filename), content_type: "application/octet-stream",
      byte_size: byte_size.to_i, kind: KIND_UNREAD, refusal: refusal
    )
  end

  def self.too_large(name, size, limit, kind = nil)
    what = { KIND_IMAGE => "an image", KIND_PDF => "a PDF", KIND_TEXT => "a text file" }.fetch(kind, "a file")
    "#{name} is #{human_size(size)}, and Halon reads #{what} up to #{human_size(limit)}."
  end

  def self.human_size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, precision: 2)

  # Magic bytes decide an image or a PDF, so a renamed file is read for what it is. Anything else is text only when it
  # looks like text.
  def self.detect(name, bytes)
    type = Marcel::MimeType.for(StringIO.new(bytes), name: name)
    return [ KIND_IMAGE, type ] if IMAGE_TYPES.include?(type)
    return [ KIND_PDF, PDF_TYPE ] if type == PDF_TYPE
    return [ KIND_TEXT, TEXT_TYPE ] if text_named?(name, type) && Chat::Attachment::Intake.text_bytes?(bytes)

    nil
  end

  def self.text_named?(name, type)
    extension = File.extname(name).delete_prefix(".").downcase
    TEXT_EXTENSIONS.include?(extension) || TEXT_NAMES.include?(name.downcase) ||
      type.start_with?("text/") || TEXT_TYPES.include?(type)
  end

  def self.clean_name(filename)
    File.basename(filename.to_s).gsub(/[[:cntrl:]]/, "").strip.truncate(200).presence || "file"
  end

  # Encrypted before it leaves for the object store, with the same keys as every encrypted column.
  def self.store(bytes)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(ActiveRecord::Encryption.encryptor.encrypt(bytes)), filename: "chat-attachment",
      content_type: "application/octet-stream", identify: false
    )
  end

  def bytes
    return "".b unless blob

    @bytes ||= ActiveRecord::Encryption.encryptor.decrypt(blob.download).b
  end

  def image? = kind == KIND_IMAGE

  def unread? = kind == KIND_UNREAD

  def sent? = chat_id.present?

  # Only the person who uploaded it until it is sent, and then only whoever may read the chat it went with.
  def readable_by?(member)
    return false unless member
    return uploaded_by_id == member.id unless sent?

    owner = chat&.owner
    owner.respond_to?(:watchable_by?) && owner.watchable_by?(member.user)
  end

  # Joins the message it was sent with. A text too long to hand over whole is kept as a saved result, which the agent
  # reads the rest of by line or by search.
  def join!(message, position:)
    chat = message.chat
    keep = text.present? && text.length > chat.result_limit
    saved = chat.saved_results.keep!(tool_name: "file #{filename}", text: text) if keep
    update!(chat: chat, message: message, queued_message: nil, saved_result: saved || saved_result, position: position)
  end

  private

  def let_go_of_bytes
    blob&.purge_later
  end
end
