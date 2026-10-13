# What a chat's agent is told besides its manual: who it acts for and how things stand around the chat. A provider caches
# a chat from its start, and OpenRouter routes it by its opening, so only what holds for the whole chat goes in the
# instructions (stable). What can change between turns (current) is sent after the chat on every model call and never
# saved (FirefightAi::AgentLoop), so a changed plan or memory never moves what the provider cached in front of it.
class Conversation::Context
  RUNS_REMEMBERED = 5

  def initialize(conversation, turn)
    @conversation = conversation
    @turn = turn
  end

  # The handbook changes only when someone edits it, and it is the largest part, so it is read from the cache with the
  # instructions rather than sent afresh on every call. An edit is one cache miss for the chats running then.
  def stable = handbook_line

  # Each line can change between turns: who asks, the day, the incident's status and who directs it, the investigations,
  # the instructions and memories, which depend on who asks and grow during the chat, and the plans. hand_memories counts
  # the memories given as used by this chat, which a turn does and reading a chat back for the bench does not.
  def current(hand_memories: true)
    [ asker_line, today_line, incident_line, directing_line, investigations_line, instructions_line, memories_line(hand_memories), plans_line ].compact.join("\n")
  end

  private

  # Who the agent acts for, so it can answer what they may do and say who else can.
  def asker_line
    asker = @turn.asker
    return "You are acting for nobody known, so every tool will refuse." unless asker
    return issue_line(asker) if @conversation.issue?

    "You are acting for #{asker.display_name}, whose role in this workspace is #{asker.role}. Owners and admins can change settings and permissions, members respond to incidents."
  end

  # Someone asked in an issue in a connected tracker, whose words and what the tracker gathered around them are in the
  # chat. Every answer is posted there, where anyone who can see the issue reads it.
  def issue_line(agent)
    session = @conversation.issue_session
    issue = [ session&.issue_key, session&.issue_url ].compact.join(" ")
    "You were asked in #{session&.place || 'a tracker'}#{" issue #{issue}" if issue.present?}, by someone assigning the issue to " \
      "Firefight or mentioning it. You act as #{agent.actor_display_name}, Firefight's own agent, which holds only the permissions an " \
      "admin granted it, never the person's. Your answer is posted in the issue, where anyone who can see it reads it."
  end

  # The day only. A plan's time is worked out from it.
  def today_line = "Today is #{Time.current.utc.strftime('%A %-d %B %Y')} (UTC)."

  # What Halon is carrying out in this chat, so a goal is never dropped between turns.
  def plans_line
    chat = @conversation.chat
    chat && Conversation::Plans.for_halon(chat)
  end

  def incident_line
    incident = @conversation.incident
    return nil unless incident

    "You are in the channel for #{incident.identifier} #{incident.name}, status #{incident.incident_status.name}."
  end

  # Anyone in an incident's channel can ask in the same thread, so Halon is told whose direction it follows when they
  # disagree. It is whoever holds the role the handbook names, the Incident Lead unless it names another.
  def directing_line
    incident = @conversation.incident
    return nil unless incident && @conversation.chat_record.speakers_named?

    role = Chat::HandbookPage.directing_role(@conversation.workspace)
    return nil unless role

    holder = incident.role_holder(role)
    who = holder ? "#{holder.display_name}, who holds #{role.name}" : "whoever holds #{role.name}, which nobody holds yet, so ask the people here to assign it before acting on directions that conflict"
    "Several people can write to you in this thread, and each message starts with who wrote it. In #{incident.identifier} you take direction from #{who}. " \
      "#{Chat::HandbookPage::Reading::CONFLICTING}"
  end

  # How the workspace works, read first on every turn. Short pages come whole and long ones are named for search_handbook.
  def handbook_line
    lines = Chat::HandbookPage.halon_lines(@conversation.workspace)
    return nil if lines.empty?

    "#{Chat::HandbookPage::HANDBOOK_HEADING}\n#{lines.join("\n\n")}"
  end

  # How people here want Halon to work on what this chat touches, most specific last.
  def instructions_line
    notes = Chat::Instruction.for_subjects(@conversation.workspace, Chat::Memory.subjects_for(@conversation.incident), principal: @turn.asker)
    return nil if notes.empty?

    "Instructions from people in this workspace, headed by where each applies. Follow them, the more specific one winning " \
      "where two differ. They say how to work, and what happened comes from what you read:\n#{notes.map { |note| "- #{note.line}" }.join("\n")}"
  end

  # What the workspace learned about what this chat touches, so it starts from what is known. Each counts as used once
  # for the whole chat.
  def memories_line(hand_memories)
    memories = Chat::Memory.starting_with(@conversation.workspace, Chat::Memory.subjects_for(@conversation.incident), principal: @turn.asker)
    return nil if memories.empty?

    Chat::Memory.handed_to!(memories, @conversation) if hand_memories && @turn.changes_memory?

    "What this workspace remembers. Each is a hunch to check against live results, and only a confirmed one was vouched " \
      "for by a person, so say so when you rely on one that is not. When a result contradicts one, dispute it with " \
      "dispute_memory:\n#{memories.map { |memory| "- #{memory.line}" }.join("\n")}"
  end

  # A run answers on its own, after the turn that started it ended, so the chat is told how its runs went.
  def investigations_line
    runs = @conversation.investigations.seen.includes(:finding).order(created_at: :desc).limit(RUNS_REMEMBERED).to_a
    return nil if runs.empty?

    lines = runs.reverse.map do |run|
      outcome = run.finding&.summary || run.stopped_because || "still running"
      "- #{run.question_for_model || run.incident&.identifier}: #{outcome}"
    end
    "Investigations started from this chat, and how each went:\n#{lines.join("\n")}"
  end
end
