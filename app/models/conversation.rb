# A person talking to the agent, which does the work the question needs itself. An investigation is the saved record of a
# run someone asked for, and the two share the loop, the tools and the saved chat.
class Conversation < ApplicationRecord
  KIND_CHANNEL = "channel"
  KIND_PERSONAL = "personal"
  # A person writing to Halon in their direct messages, answered in the thread they wrote in.
  KIND_DIRECT = "direct"
  # Another agent asking over MCP, one chat per principal, as that principal.
  KIND_MCP = "mcp"
  # Someone assigning an issue in a connected tracker to Firefight's app, or mentioning it there, answered in the issue
  # (Conversation::IssueSession). It acts as Firefight's own agent, never as a person, and like a chat in a channel it
  # lives only where it was asked, so no dashboard lists or opens it.
  KIND_ISSUE = "issue"
  KINDS = [ KIND_CHANNEL, KIND_PERSONAL, KIND_DIRECT, KIND_MCP, KIND_ISSUE ].freeze
  # One person's own chats, listed on their dashboard wherever they were asked.
  OWN_KINDS = [ KIND_PERSONAL, KIND_DIRECT ].freeze
  # A direct message after a day without a word starts a new chat, since the old one is about something else by then.
  DIRECT_QUIET_AFTER = 1.day

  TITLE_LIMIT = 80
  PREVIEW_LIMIT = 90
  # How long an owed answer counts as still coming. Shared with the reply job's lock, so the two give up together.
  REPLY_CEILING = 30.minutes
  SEARCH_LIMIT = 20
  UNTITLED = "New chat".freeze

  # The title is the person's own words, so it is encrypted like the messages.
  encrypts :title

  belongs_to :workspace
  belongs_to :subject, polymorphic: true, optional: true
  # A person, a service key or an agent, whoever the way in resolved to.
  belongs_to :started_by, polymorphic: true, optional: true
  has_one :chat, as: :owner, dependent: :destroy
  # The runs this chat started. A run outlives the chat that asked for it.
  has_many :investigations, dependent: :nullify
  # Cards that asked the person about a memory something contradicted in this chat, before Halon checked memories itself.
  has_many :memory_posts, class_name: "Chat::MemoryPost", dependent: :delete_all
  # Handbook edits Halon proposed in this chat. They outlive it on the Handbook page.
  has_many :handbook_proposals, class_name: "Chat::HandbookProposal", dependent: :nullify
  # Workflows Halon made from this chat, shown here as cards.
  has_many :workflows, foreign_key: :origin_conversation_id, inverse_of: :origin_conversation, dependent: :nullify
  # Skills Halon proposed in this chat. They outlive it on the Skills page.
  has_many :skill_proposals, -> { where(author_kind: Chat::CustomSkill::Version::AUTHOR_HALON) }, class_name: "Chat::CustomSkill::Version",
                                                                                                  dependent: :nullify
  # Pull request news for this chat. The notice belongs to its session and outlives the chat.
  has_many :pull_request_notices, class_name: "CodeAgentSession::Notice", dependent: :nullify, inverse_of: :conversation
  # Code changes from this chat that reached their spending limit, each asking Continue or Stop. They belong to their session.
  has_many :code_pauses, class_name: "CodeAgentSession::Pause", dependent: :nullify, inverse_of: :conversation
  # Every thread a direct message chat was asked in, so a reply in an earlier one still reaches it.
  has_many :thread_links, class_name: "Conversation::ThreadLink", dependent: :delete_all
  # The tracker's session a chat started in an issue answers in.
  has_one :issue_session, class_name: "Conversation::IssueSession", dependent: :delete

  validates :kind, inclusion: { in: KINDS }
  validates :max_turns, :max_spend_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :personal, -> { where(kind: KIND_PERSONAL) }
  scope :own_for, ->(member) { where(kind: OWN_KINDS, started_by: member) }
  scope :archived, -> { where.not(archived_at: nil) }
  # Archived last, so a list that loads page by page reaches them at the end.
  scope :in_reading_order, -> { order(Arel.sql("archived_at IS NOT NULL, pinned_at DESC NULLS LAST, updated_at DESC")) }

  # The chat an outside agent has with Halon, one per principal and per incident it asks about, so
  # questions carry on and a question about one incident never lands in another's chat.
  def self.for_mcp!(workspace:, principal:, incident: nil)
    scope = workspace.conversations.where(kind: KIND_MCP, started_by: principal, subject: incident)
    scope.first || begin
      limits = workspace.conversation_limits
      workspace.conversations.create!(
        kind: KIND_MCP, started_by: principal, subject: incident,
        max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
      )
    end
  end

  # From a platform thread, where no controller asked the gateway. A question spends money, so it is allowed and ledgered
  # like one in the dashboard, but never held by an approval rule, since nothing in a thread could pick it up again.
  # Raises AbilityGateway::Denied, and returns what the block returns.
  def self.ask_from_thread!(asker:, workspace:, incident:, source:, &)
    AbilityGateway.authorize!(
      principal: asker, action_key: Ability::Action::INVESTIGATIONS_CREATE, workspace: workspace, holdable: false,
      context: { source: source, incident_id: incident&.id }, &
    )
  end

  # From a tracker's issue, where nobody in Firefight asked. Firefight's own agent asks, which an admin allowed by
  # installing the app there, and it is ledgered like any question, never held by an approval rule, since nothing in the
  # issue could pick it up again. asked_by_label names who asked there. Returns what the block returns.
  def self.ask_from_issue!(workspace:, asked_by_label:, &)
    AbilityGateway.record_unattended!(
      principal: SystemAgent.investigator, action_key: Ability::Action::INVESTIGATIONS_CREATE, workspace: workspace, params: {},
      context: { source: AbilityGateway::SOURCE_CONVERSATION, triggered_by_label: asked_by_label }, &
    )
  end

  # A member answering, in a tracker's issue, a call the chat there paused on, as pressing a button in a channel does.
  # They must be allowed to ask Halon, and it is ledgered as theirs, never held, since nothing in the issue could pick it
  # up again. Answers false, having run nothing, when they may not.
  def self.answer_in_issue!(member:, workspace:, asked_by_label:, &)
    AbilityGateway.authorize!(
      principal: member, action_key: Ability::Action::INVESTIGATIONS_CREATE, workspace: workspace, holdable: false,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, triggered_by_label: asked_by_label }, &
    )
    true
  rescue AbilityGateway::Denied
    false
  end

  # The chat a platform thread belongs to, whether it started there or a direct message chat carried on in it.
  def self.in_thread(workspace, channel_id, thread_id)
    workspace.conversations.find_by(channel_id: channel_id, thread_id: thread_id) ||
      workspace.conversations.joins(:thread_links).find_by(conversation_thread_links: { channel_id: channel_id, thread_id: thread_id })
  end

  # The direct message chat a new message from this person carries on, while it has not gone quiet or been put away.
  def self.direct_carrying_on(member)
    latest = member.workspace.conversations.where(kind: KIND_DIRECT, started_by: member, archived_at: nil).order(updated_at: :desc).first
    latest if latest&.carries_on?
  end

  def self.start_direct!(workspace:, member:, channel_id:, thread_id:, subject: nil)
    limits = workspace.conversation_limits
    workspace.conversations.create!(
      kind: KIND_DIRECT, started_by: member, subject: subject, channel_id: channel_id, thread_id: thread_id,
      max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    )
  end

  # The chat a tracker's session belongs to, or nil.
  def self.in_issue_session(integration, session_id)
    joins(:issue_session).find_by(conversation_issue_sessions: { integration_id: integration.id, session_id: session_id })
  end

  # A session someone opened in an issue. The chat acts as Firefight's own agent, and is named for the issue.
  def self.start_in_issue!(integration:, session_id:, title:, issue_key: nil, issue_url: nil, asked_by: nil)
    workspace = integration.workspace
    limits = workspace.conversation_limits
    transaction do
      workspace.conversations.create!(
        kind: KIND_ISSUE, started_by: SystemAgent.investigator, title: title.to_s.truncate(TITLE_LIMIT).presence,
        max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
      ).tap do |started|
        started.create_issue_session!(workspace: workspace, integration: integration, session_id: session_id, issue_key: issue_key,
                                      issue_url: issue_url, asked_by: asked_by)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    in_issue_session(integration, session_id) || raise
  end

  # model is one the person picked before the first question, which the caller has checked is offered.
  # subject is what the chat was started beside, such as a workflow on its canvas, which the agent is told about.
  def self.start_personal!(workspace:, member:, model: nil, subject: nil)
    limits = workspace.conversation_limits
    workspace.conversations.create!(
      kind: KIND_PERSONAL, started_by: member, subject: subject,
      max_turns: limits.max_turns, max_spend_cents: limits.max_spend_cents
    ).tap { |started| started.choose_model!(model) if model.present? }
  end

  # The nav and the socket ask this, so neither offers what the gateway would refuse.
  def self.readable_by?(member)
    return false unless member

    member.may?(Ability::Action::RESOURCE_CHATS, Ability::Action::ACTION_READ, member.workspace)
  end

  # Titles and messages are encrypted, so matching happens in Ruby, not SQL. shown reads the platform's markup as the page
  # shows it, given texts and answering each mapped to how it reads, so a chat is found by what people see as well as by
  # what is stored.
  def self.search_for(member, text, limit: SEARCH_LIMIT, shown: nil)
    wanted = text.to_s.strip.downcase
    return [] if wanted.empty?

    chats = with_previews(own_for(member).in_reading_order)
    said = chats.flat_map { |conversation| [ conversation.title_question, conversation.preview_question ] }.compact.uniq
    read = shown && said.any? ? shown.call(said) : {}
    chats.select { |conversation| conversation.searched_text(read).downcase.include?(wanted) }.first(limit)
  end

  # Conversations as a list shows them, each with its chat as listed and that chat's previews (Chat.preload_previews).
  def self.with_previews(conversations)
    conversations = conversations.to_a
    ActiveRecord::Associations::Preloader.new(records: conversations, associations: :chat, scope: Chat.listed).call
    Chat.preload_previews(conversations.map(&:chat))
    conversations
  end

  def personal? = kind == KIND_PERSONAL

  def mcp? = kind == KIND_MCP

  def direct? = kind == KIND_DIRECT

  def issue? = kind == KIND_ISSUE

  def belongs_to_one_person? = OWN_KINDS.include?(kind)

  # A turn still running counts as talking, so a message sent while Halon works always joins it.
  def carries_on? = answer_owed? || updated_at > DIRECT_QUIET_AFTER.ago

  # A direct message chat answers in the thread it was last asked in. A message sent while a turn runs joins that turn,
  # whose answer is already being written in the thread it began in, so the chat moves only between turns.
  def asked_in_thread!(asked_channel_id, asked_thread_id)
    thread_links.create_or_find_by!(workspace: workspace, channel_id: asked_channel_id, thread_id: asked_thread_id)
    moved = self.class.where(id: id).where("answer_owed_since IS NULL OR answer_owed_since <= ?", REPLY_CEILING.ago)
                .update_all(channel_id: asked_channel_id, thread_id: asked_thread_id)
    reload if moved == 1
  end

  # The platform a direct message chat lives in, as people know it. A dashboard chat lives on the dashboard.
  def asked_in = (Platforms.display_name(workspace.platform) if direct?)

  # The dashboard reads a chat from elsewhere but never asks in it, since the answer is written where it was asked.
  def ask_blocked_reason
    "This chat is in #{asked_in}, so carry on there." if direct?
  end

  # Who a turn acts as. A chat in an issue always acts as the agent it was started as, whoever confirmed a call or
  # approved one for it, since a machine never borrows a person's reach. Any other acts as the asker, or whoever started it.
  def turn_asker(asker_id)
    return started_by if issue?

    workspace.workspace_memberships.find_by(id: asker_id) || started_by
  end

  # What the person and the agent said to each other is the conversation, so it is never put away.
  # The work in between is, meaning the tool calls, their results and the agent's nudges to itself.
  def keeps_in_memory?(message)
    Chat::Message::READABLE_ROLES.include?(message.role) && !message.nudge && message.ruby_llm_tool_calls.empty?
  end

  # A conversation holds no records of its own beyond the chat, so there is nothing to add.
  def memory_brief = nil

  # One box for the whole conversation, so a follow up question reads code it already has.
  CODE_BOX_PREFIX = "conversation-".freeze

  def code_box_key = "#{CODE_BOX_PREFIX}#{id}"

  # Saved before the job runs, so the person sees it at once and a retried job asks only once. From here an answer is owed.
  # While a turn is running the question waits and joins that turn at the agent's next step, so the person can steer it.
  # A follow up in an issue waits the same way, whoever wrote it there.
  # Files go with the question, and a question may be files alone.
  # context is what Halon needs to read with the question and the person never wrote, such as the message they replied to.
  # It goes before the question as a note the page does not show, now or when a running turn takes the question.
  # as_written is the question as the chat platform sent it, when question is the model's reading of it.
  def ask!(question, asker: nil, files: [], context: nil, as_written: nil)
    if (asker.is_a?(WorkspaceMembership) || issue?) && answer_owed?
      return chat_record.queue_message!(question.to_s, sender: (asker if asker.is_a?(WorkspaceMembership)), files: files, as_written: as_written, context: context)
    end

    chat_record.nudge!(context) if context
    message = chat_record.add_person_message!(question, sender: asker, as_written: as_written)
    chat_record.attach_files!(message, files)
    named = (as_written || question).presence || files.map(&:filename).to_sentence
    update!(title: named.truncate(TITLE_LIMIT)) if title.blank?
    expect_reply!
  end

  # The page shows the agent working from this, never from the shape of the last message, which the empty reply
  # RubyLLM saves before the model answers changes within milliseconds of the question.
  def expect_reply! = update_in_place!(answer_owed_since: Time.current, reply_failed: false)

  def reply_delivered! = update_in_place!(answer_owed_since: nil, reply_recovered_at: nil)

  # The turn ended without an answer and its last word in the chat says why, so a caller waiting on it can tell that from
  # an answer.
  def reply_failed! = update_in_place!(answer_owed_since: nil, reply_recovered_at: nil, reply_failed: true)

  def confirmation_posted!(message_id) = update_in_place!(confirmation_message_id: message_id)

  # The answer a turn is writing in its thread, kept until it is finished there, so a lost turn's answer can be ended
  # where it stopped.
  def answer_started!(message_id) = update_in_place!(answer_message_id: message_id, answer_shown: false)

  def answer_shown! = update_in_place!(answer_shown: true)

  def answer_finished! = update_in_place!(answer_message_id: nil, answer_shown: false)

  # A person's message the platform marked as being worked on, marked done once a turn answers it.
  def acknowledged!(message_id)
    return if message_id.blank?

    self.class.where(id: id).update_all([ "acknowledged_message_ids = array_append(array_remove(acknowledged_message_ids, ?::varchar), ?::varchar)",
                                          message_id, message_id ])
  end

  # How many times in all a mark the platform could not make just now is tried, so one message never fails without end.
  MARK_ATTEMPTS = 3

  # A mark that failed for now goes back for the next answer until it was tried MARK_ATTEMPTS times. One statement, so
  # two turns ending together count each try once.
  def mark_again!(message_id)
    tried = "COALESCE((mark_attempts ->> :id)::int, 1)"
    kept = self.class.where(id: id).where("#{tried} < :cap", id: message_id, cap: MARK_ATTEMPTS).update_all([
      "acknowledged_message_ids = array_append(array_remove(acknowledged_message_ids, CAST(:id AS varchar)), CAST(:id AS varchar)), " \
      "mark_attempts = mark_attempts || jsonb_build_object(CAST(:id AS text), #{tried} + 1)", { id: message_id }
    ])
    mark_settled!(message_id) if kept.zero?
  end

  def mark_settled!(message_id)
    self.class.where(id: id).where("jsonb_exists(mark_attempts, :id)", id: message_id)
              .update_all([ "mark_attempts = mark_attempts - CAST(:id AS text)", { id: message_id } ])
  end

  # The marked messages, taken under a lock so two turns ending together never mark one twice.
  def take_acknowledged!
    self.class.transaction do
      taken = self.class.where(id: id).lock.pick(:acknowledged_message_ids).to_a
      self.class.where(id: id).update_all(acknowledged_message_ids: []) if taken.any?
      taken
    end
  end

  # A turn whose job died is run again at most once. One statement on the turn as it was read, so two sweeps cannot both
  # run it, and a turn started since is not touched. The mark goes once the turn ends.
  def rerun_lost_reply!(owed)
    self.class.where(id: id, answer_owed_since: owed, reply_recovered_at: nil).update_all(reply_recovered_at: Time.current) == 1
  end

  # Ends a lost turn, once, under the same guard.
  def end_lost_reply!(owed)
    self.class.where(id: id, answer_owed_since: owed).update_all(answer_owed_since: nil, reply_recovered_at: nil, reply_failed: true) == 1
  end

  NOTHING_TO_STOP = "Halon is not working on anything in this chat.".freeze
  # Said once Stop is pressed. The answer then ends with Stopped as soon as the worker hears it.
  STOPPING = "Halon is stopping.".freeze

  def stop_blocked_reason = (NOTHING_TO_STOP unless answer_owed?)

  # The worker reads the stop from the chat's row, between steps and while a model call runs.
  def request_stop! = chat_record.cancel

  # A turn owed this long belongs to a dead worker, and neither the page nor the queue waits on it.
  def answer_owed? = answer_owed_since.present? && answer_owed_since > REPLY_CEILING.ago

  # Saved, so the notice is still there on the next visit.
  def note!(text) = chat_record.notice!(text)

  def display_title = title.presence || UNTITLED

  def pinned? = pinned_at.present?

  def archived? = archived_at.present?

  def pin!(pinned) = update_in_place!(pinned_at: pinned ? Time.current : nil)

  def archive!(archived) = update_in_place!(archived_at: archived ? Time.current : nil)

  def rename!(new_title) = update_in_place!(title: new_title.to_s.strip.truncate(TITLE_LIMIT))

  def preview
    Chat::Chart::Marker.strip(chat&.last_readable_message&.content.to_s).truncate(PREVIEW_LIMIT)
  end

  # A direct message chat is asked only in the platform, so what the person said is in the platform's own markup, which
  # the page shows as the platform reads it (PlatformAdapter#messages_as_text). A message saved since keeps the words as
  # written beside the model's reading, whatever the chat.
  def said_in_platform_markup? = direct?

  # A person's message as the platform sent it, or nil when it was not written there.
  def said_in_platform(message)
    return nil unless message&.role == Chat::Message::ROLE_USER

    message.as_written || (message.content if said_in_platform_markup?)
  end

  # The question the title was taken from, while the chat still goes by it. A name someone gave it is their own words.
  def title_question
    question = said_in_platform(chat&.first_question)
    question if question && title.present? && title == question.truncate(TITLE_LIMIT)
  end

  # What a search matches: the title and preview as stored and, for words in the platform's markup, as the page shows them.
  def searched_text(read)
    [ display_title, preview, read[title_question], read[preview_question] ].compact.join(" ")
  end

  # The person's last message, when the preview shows theirs rather than the agent's.
  def preview_question = said_in_platform(chat&.last_readable_message)

  def watchable_by?(user)
    belongs_to_one_person? && started_by.is_a?(WorkspaceMembership) && started_by.user_id == user&.id && self.class.readable_by?(started_by)
  end

  # Two questions asked at once share the chat that won the insert.
  def chat_record
    chat || Chat.open!(owner: self, workspace: workspace, model_choice: ai_model).tap { |opened| self.chat = opened }
  rescue ActiveRecord::RecordNotUnique
    reload_chat
  end

  def ai_model = picked_model_choice || workspace_model

  # What every chat runs on unless a person picked another, and what helpers and investigations keep.
  def workspace_model = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace)

  # The model a person picked for their dashboard chat, while the workspace's account still offers it. Nil follows the
  # workspace's main model. Chats in Slack and over MCP always do.
  def picked_model_choice
    return nil unless personal? && chosen_model.present?

    model_menu.choice(chosen_model)
  end

  def model_menu = Conversation::ModelMenu.for(workspace)

  def model_blocked_reason(model, menu: model_menu) = menu.blocked_reason(model)

  # Picking the main model clears the pick, so the chat follows the workspace's model if an admin changes it.
  def choose_model!(model, menu: model_menu)
    update_in_place!(chosen_model: model.to_s == menu.default_model ? nil : model.to_s)
  end

  # The ledger and the prompt want an incident. A conversation about nothing has none.
  def incident
    subject if subject_type == Incident.name
  end

  def incident_id
    subject_id if subject_type == Incident.name
  end

  # Why the member cannot ask Halon in a new or open chat, as a sentence, or nil when they can.
  def self.asking_blocked_reason(member)
    workspace = member.workspace
    return Investigation.unavailable_reason(workspace) unless Investigation.available_for?(workspace)

    key = Ability::Action::INVESTIGATIONS_CREATE
    action = Ability::Action.lookup(key, workspace)
    return if action && AbilityGateway.permitted?(member, action, key, workspace, {})

    "Asking Halon needs the permission to ask Halon and start investigations, which a workspace admin can grant."
  end

  # The person's newest chat started beside something, such as a workflow's canvas, that they have not archived.
  def self.beside(subject, member)
    own_for(member).where(subject: subject, archived_at: nil).order(updated_at: :desc).first
  end

  # The workflow a chat was started beside on its canvas.
  def workflow
    subject if subject_type == Workflow.name
  end

  # Added in SQL, so a caller holding a stale copy cannot write an old total back.
  def add_turn!(turns:, spent_micros:)
    self.class.where(id: id).update_all([
      "turns_used = turns_used + ?, spent_micros = spent_micros + ?, updated_at = ?",
      turns, spent_micros, Time.current
    ])
  end

  private

  # Tidying a chat is not talking in it, so it keeps its place in the list.
  def update_in_place!(attributes)
    self.record_timestamps = false
    update!(attributes)
  ensure
    self.record_timestamps = true
  end
end
