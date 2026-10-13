# The stretch of a chat a page reads at once. A chat opens on its newest PAGE messages and reads PAGE older ones each
# time the person scrolls up (before, the oldest message the page holds). A page that reloads names the oldest message it
# holds (from) and gets everything since, so a reload keeps the stretch on screen. Whatever else the chat places by time
# is read for the same stretch, so nothing from further back shows beside newer messages and nothing in it is missing.
class Chat::Window
  PAGE = 50

  # chat may be nil, for a conversation nobody has asked anything in yet. A before or from that is not one of this chat's
  # messages reads as nothing older and as the newest page.
  def initialize(chat, before: nil, from: nil)
    @chat = chat
    @before = chat && before.presence && readable.find_by(id: before.to_s)
    @asked_before = before.present?
    @from = chat && !@asked_before && from.presence && readable.find_by(id: from.to_s)
  end

  # Oldest first. For a page asked for by before, only that page.
  def messages
    return Chat::Message.none unless @chat && (!@asked_before || @before)

    readable.where(id: page_ids)
  end

  # The oldest message in the stretch, which a page asks the next older page by.
  def first = page.first

  def older?
    load_page
    @older
  end

  # Since when the stretch runs, or nil when it reaches the start of the chat and so takes everything placed before too.
  def starts_at = older? ? first.created_at : nil

  # Those of rows placed at a time that fall in the stretch. at is the time each row's card is placed at in the chat.
  def placed(scope, at = scope.klass.arel_table[:created_at])
    starts_at ? scope.where(at.gteq(starts_at)) : scope
  end

  # Those of rows drawn under a step that belong to a step in the stretch.
  def stepped(scope)
    starts_at ? scope.where(tool_call_id: step_keys) : scope
  end

  # Inertia's paging, newest first, so its next page is the older one and starts right before the oldest message shown.
  def scroll_metadata(page_name)
    { page_name: page_name, current_page: first&.id, previous_page: nil, next_page: (first.id if older?) }
  end

  private

  def readable = @chat.readable_messages

  def page
    load_page
    @page
  end

  def page_ids = page.map(&:id)

  def load_page
    return if defined?(@page)

    @older = false
    @page = read_page
  end

  def read_page
    return [] if !@chat || (@asked_before && !@before)
    return since(@from) if @from

    newest_before(@before)
  end

  # One row past a page says whether there is an older one, without a count.
  def newest_before(cursor)
    rows = readable.reorder(created_at: :desc, id: :desc)
    rows = rows.where("(chat_messages.created_at, chat_messages.id) < (?, ?)", cursor.created_at, cursor.id) if cursor
    found = rows.select(:id, :created_at).limit(PAGE + 1).to_a
    @older = found.size > PAGE
    found.first(PAGE).reverse
  end

  def since(cursor)
    @older = readable.where("(chat_messages.created_at, chat_messages.id) < (?, ?)", cursor.created_at, cursor.id).exists?
    readable.reorder(:created_at, :id).where("(chat_messages.created_at, chat_messages.id) >= (?, ?)", cursor.created_at, cursor.id)
      .select(:id, :created_at).to_a
  end

  def step_keys
    from_first = readable.where("(chat_messages.created_at, chat_messages.id) >= (?, ?)", first.created_at, first.id).select(:id)
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: from_first).select(:tool_call_id)
  end
end
