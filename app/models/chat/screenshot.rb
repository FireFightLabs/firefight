# A page as Halon's browser saw it, one per screen size a check ran on, kept with the chat whose check took it. The bytes
# sit in the object store encrypted with the app's own keys, like a file a person attached, and go when the chat goes.
# A check that stopped before something the page would send keeps what it would have sent, which the person is shown
# when Halon asks to send it.
class Chat::Screenshot < ApplicationRecord
  CONTENT_TYPE = "image/jpeg".freeze
  # The largest image a check hands back. A viewport's JPEG is far smaller, so anything past this is not a screenshot.
  MAX_BYTES = 5.megabytes
  # A thread gets at most this many under one answer, the first ones taken.
  POSTED_LIMIT = 4
  # How long a stopped check stays what a send is confirmed against. Past this the page may have moved on, so Halon
  # looks again first.
  SEND_FRESH_FOR = 30.minutes

  # What a platform needs to post one.
  Post = Data.define(:caption, :filename, :jpeg)

  belongs_to :chat
  belongs_to :remediation_step, class_name: "Investigation::RemediationStep", optional: true

  has_one_attached :sealed

  encrypts :page_url
  encrypts :title
  encrypts :would_send
  serialize :would_send, coder: JSON

  validates :viewport, inclusion: { in: Chat::BrowserCheck::VIEWPORTS.keys }

  scope :in_order, -> { order(:created_at, :position) }

  # Keeps the screenshot of each screen size a check answered, skipping one that is missing or not an image, so a check
  # never fails for want of its picture. Returns the ones kept.
  def self.record!(chat, viewports, tool_call_id: nil, digest: nil, remediation_step: nil, step_position: nil)
    Array(viewports).each_with_index.filter_map do |viewport, index|
      bytes = Base64.decode64(viewport["screenshot"].to_s)
      next if bytes.empty? || bytes.bytesize > MAX_BYTES || !jpeg?(bytes)

      stopped = viewport["stopped"].to_h
      chat.screenshots.create!(
        tool_call_id: tool_call_id, remediation_step: remediation_step, step_position: step_position, position: index, viewport: viewport["name"].to_s,
        page_url: viewport["final_url"].to_s.truncate(2_000), title: viewport["title"].to_s.truncate(300), byte_size: bytes.bytesize,
        stopped_step: (stopped["step"].to_i if stopped["would_send"].present?), would_send: stopped["would_send"].presence,
        check_digest: digest, sealed: sealed(bytes)
      )
    end
  rescue ActiveRecord::RecordInvalid => error
    Rails.logger.warn({ event: "chat.screenshot_not_kept", chat_id: chat.id, error: error.message }.to_json)
    []
  end

  def self.jpeg?(bytes) = bytes.byteslice(0, 3) == "\xFF\xD8\xFF".b

  def self.sealed(bytes)
    { io: StringIO.new(ActiveRecord::Encryption.encryptor.encrypt(bytes)), filename: "chat-screenshot",
      content_type: "application/octet-stream", identify: false }
  end

  # The page a check stopped on before step, in this chat, while it is fresh enough to send from. digest names the
  # address, steps and login, so a send is only ever confirmed against the very check the person was shown.
  # fresh: false finds it however old, for a confirmation drawn again later.
  def self.stopped_before(chat, digest, step, fresh: true)
    return if chat.nil?

    found = chat.screenshots.where(check_digest: digest, stopped_step: step)
    found = found.where(created_at: SEND_FRESH_FOR.ago..) if fresh
    found.order(created_at: :desc).first
  end

  # The screenshots to post under an answer, at most POSTED_LIMIT, and how many were left out.
  def self.posted_under_answer(screenshots)
    all = screenshots.to_a
    return if all.empty?

    yield all.first(POSTED_LIMIT).map(&:to_post), [ all.size - POSTED_LIMIT, 0 ].max
  end

  def bytes
    return "".b unless sealed.attached?

    @bytes ||= ActiveRecord::Encryption.encryptor.decrypt(sealed.download).b
  end

  def content_type = CONTENT_TYPE

  def filename = "#{viewport}-#{created_at.utc.strftime('%Y%m%d-%H%M%S')}.jpg"

  def viewport_label = Chat::BrowserCheck.viewport_label(viewport)

  # One line on what the picture shows, as the page and a platform name it.
  def caption
    page = [ title.presence, page_url.presence ].compact.join(" at ")
    stopped = stopped_step ? ", before step #{stopped_step}, which would send data" : ""
    "#{viewport_label}: #{page.presence || 'the page'}#{stopped}"
  end

  def to_post = Post.new(caption: caption, filename: filename, jpeg: bytes)

  # The request the page would have sent, as the person confirming it reads it: the method and address, then each field.
  def would_send_rows
    sent = would_send.to_h
    return [] if sent.empty?

    [ [ "Sends", "#{sent['method']} #{sent['url']}" ], *Array(sent["fields"]).first(Chat::BrowserCheck::FIELDS_SHOWN).map { |field| [ field["name"].to_s, field["value"].to_s ] } ]
  end

  # Whoever may read the chat may see what its browser saw. A run's chat is shown through the run's own pages.
  def readable_by?(member)
    owner = chat&.owner
    member.present? && owner.respond_to?(:watchable_by?) && owner.watchable_by?(member.user)
  end
end
