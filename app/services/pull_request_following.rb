# Halon owns the pull requests it opens. Each one is read through its code host after it opens, whenever the host says
# something about it, its checks or its base changed, and on a sweep for hosts that send nothing. When it conflicts with
# its base, a check fails or a reviewer asks for changes, the chat it came from is told once, with the reason and Fix it,
# in the chat, its thread or the asker's direct messages. Fix it is the person's yes: the code change then runs on the
# pull request's branch as them, through the gateway and approval rules, at the start of a turn in that chat, and Halon
# says how it went. Following ends when the pull request is merged or closed.
module PullRequestFollowing
  CHECK_FAILED = "pull_request.check_failed".freeze
  COULD_NOT_FIX = "The code change could not be started, so nothing changed on the branch.".freeze

  # Where a notice is said: the chat (nil for a fix whose run was not started from one) and a thread on the platform.
  Destination = Data.define(:conversation, :channel_id, :thread_id)

  module_function

  # One read, its news said once. A pull request another worker reads is left to it.
  def check!(session, now: Time.current)
    return unless session.following? && session.integration_environment && session.claim_pull_request_check!(now)

    begin
      status = Integrations::PullRequests.status(session.integration_environment, repository: session.repository, number: session.pull_request_number)
      return ended!(session, status.state) unless status.open?
      return cleared!(session) if status.problems.empty?

      notice = CodeAgentSession::Notice.record!(session, status)
      return unless notice

      CodeAgentSession::Notice.settle_offered!(session, CodeAgentSession::Notice::STATUS_REPLACED, except: notice).each { |old| redraw!(old) }
      tell!(notice)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: CHECK_FAILED, code_agent_session_id: session.id, error: error.message.truncate(200) }.to_json)
    ensure
      session.release_pull_request_check!
    end
  end

  def ended!(session, state)
    return unless session.stop_following!(state)

    CodeAgentSession::Notice.settle_offered!(session, CodeAgentSession::Notice::STATUS_ENDED).each { |notice| redraw!(notice) }
  end

  # The problems are gone, so an offer nobody took is no longer one.
  def cleared!(session)
    CodeAgentSession::Notice.settle_offered!(session, CodeAgentSession::Notice::STATUS_CLEARED).each { |notice| redraw!(notice) }
  end

  # Followed pull requests whose interval has passed, each read by its own job.
  def sweep!
    CodeAgentSession.follow_due.pluck(:id).each { |id| PullRequestCheckJob.perform_later(id) }
  end

  # A code host's delivery about pull requests reaches the ones Halon follows through that connection at once: one it
  # names, one whose branch or base moved.
  def nudged!(environment_row, nudges)
    nudges.each do |nudge|
      following = CodeAgentSession.following.where(integration_environment_id: environment_row.id, repository: nudge.repository)
      named = following.where(pull_request_number: nudge.numbers).or(following.where(pull_request_base: nudge.branches))
                       .or(following.where(pull_request_branch: nudge.branches))
      named.each(&:check_soon!)
    end
  end

  # Said once wherever the chat it came from reads: on the dashboard, in its thread, or in the asker's direct messages
  # when it has no thread. A fix's notice whose run was not started from a chat goes to the run's thread.
  def tell!(notice)
    destination = destination_of(notice.session)
    notice.update_columns(conversation_id: destination.conversation&.id)
    Conversation::LiveDelivery.pull_request_moved(destination.conversation) if destination.conversation
    adapter = WorkspaceAdapter.for(notice.workspace)
    posted = if destination.thread_id.present?
      adapter.post_pull_request_notice(channel_id: destination.channel_id, thread_id: destination.thread_id, notice: notice)
    elsif (user_id = notice.session.principal.try(:platform_user_id)).present?
      adapter.post_pull_request_notice_to_user(user_id: user_id, notice: notice, conversation_id: destination.conversation&.id)
    end
    notice.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted.is_a?(Hash) && posted[:message_id]
  rescue AdapterError => error
    Rails.logger.warn({ event: "pull_request.untold", notice_id: notice.id, error: error.class.name }.to_json)
  end

  def redraw!(notice)
    Conversation::LiveDelivery.pull_request_moved(notice.conversation) if notice.conversation
    return if notice.message_id.blank?

    WorkspaceAdapter.for(notice.workspace).update_pull_request_notice(channel_id: notice.message_channel_id, message_id: notice.message_id, notice: notice)
  rescue AdapterError => error
    Rails.logger.warn({ event: "pull_request.redraw_failed", notice_id: notice.id, error: error.class.name }.to_json)
  end

  def destination_of(session)
    case session.place
    when Conversation then Destination.new(conversation: session.place, channel_id: session.place.channel_id, thread_id: session.place.thread_id)
    when Investigation::RemediationStep
      investigation = session.place.plan.finding.investigation
      chat = investigation.conversation
      return Destination.new(conversation: chat, channel_id: chat.channel_id, thread_id: chat.thread_id) if chat

      Destination.new(conversation: nil, channel_id: investigation.channel_id, thread_id: investigation.thread_id)
    else Destination.new(conversation: nil, channel_id: nil, thread_id: nil)
    end
  end

  # Fix it, pressed by the person the change runs as. The change runs at the start of a turn in the chat the notice was
  # told in, or in the run's thread's own chat. Answers why not, or nil.
  def fix!(notice, by:)
    blocked = notice.fix_blocked_reason(by)
    return blocked if blocked

    conversation = notice.conversation || thread_conversation(notice, by)
    return COULD_NOT_FIX unless conversation
    return notice.reload.fix_blocked_reason(by) || "This was already taken care of." unless notice.claim_fix!(by)

    notice.update_columns(conversation_id: conversation.id)
    conversation.expect_reply!
    ConversationReplyJob.perform_later(conversation.id, by.id, nil, nil, notice.id)
    redraw!(notice)
    nil
  end

  # A fix's run that was not started from a chat speaks in its thread, which is a chat of its own once someone acts there.
  def thread_conversation(notice, by)
    destination = destination_of(notice.session)
    return if destination.thread_id.blank? || by.platform_user_id.blank?

    investigation = notice.session.place.plan.finding.investigation
    Conversation::Opener.call(workspace: notice.workspace, incident: investigation.incident, channel_id: destination.channel_id,
                              thread_id: destination.thread_id, platform_user_id: by.platform_user_id)
  end

  # The code change on the pull request's branch, as the person who pressed Fix it, through the very tool a chat offers
  # them, so grants, approval rules and the ledger apply as if Halon had called it. Answers what the tool said.
  def run_fix!(turn, notice)
    session = notice.session
    row = session.integration_environment
    tool = row&.integration&.tools&.find { |each| each.writes_code? && each.enabled? && each.available? }
    return "Fix it did not run, since the code host's tool that writes code changes is no longer switched on." unless tool

    arguments = { "repo" => session.repository, "pull_request" => session.pull_request_number, "title" => fix_title(notice), "brief" => fix_brief(notice) }
    Chat::Tools::Connection.new(turn, tool).run(arguments, environment_entry: row.environment, tool_call_id: nil, shown_as: tool.model_facing_name)
  rescue StandardError => error
    Rails.logger.warn({ event: "pull_request.fix_failed", notice_id: notice.id, error: error.class.name }.to_json)
    COULD_NOT_FIX
  end

  def fix_title(notice)
    kinds = notice.kinds
    return "Merge #{notice.base} and resolve the conflict" if kinds == [ Integrations::PullRequests::PROBLEM_CONFLICT ]
    return "Fix the failing checks" if kinds == [ Integrations::PullRequests::PROBLEM_CHECKS ]
    return "Make the requested changes" if kinds == [ Integrations::PullRequests::PROBLEM_REVIEW ]

    "Bring the pull request back to mergeable"
  end

  def fix_brief(notice)
    lines = [ "#{notice.reason} The person who asked for it pressed Fix it." ]
    notice.problems.each do |problem|
      case problem["kind"]
      when Integrations::PullRequests::PROBLEM_CONFLICT
        lines << "It conflicts with #{notice.base}. Merge refs/remotes/firefight/#{notice.base}, the newest #{notice.base}, into the branch, resolve every " \
                   "conflict keeping what both sides meant, and commit the merge."
      when Integrations::PullRequests::PROBLEM_CHECKS
        lines << "These checks failed on its newest commit: #{problem['detail']}. Read why with the tools that read CI and its logs, then fix the code so they pass."
      else
        lines << "A reviewer asked for changes: #{problem['detail']}. Make them."
      end
    end
    lines.join("\n")
  end

  # What Halon reads once Fix it ran, before it tells the person how it went.
  def fixed_note(notice, said)
    "The person pressed Fix it on #{notice.session.pull_request_label} (#{notice.reason}), so you ran the code change on its branch. " \
      "It answered:\n#{FirefightAi::Evidence.frame(notice.session.pull_request_label, said.to_s)}\nTell them how it went in a few sentences. " \
      "Say whether it can merge only as the code host said it, never that a conflict is resolved unless the host says it can merge."
  end

  # What Halon hears at its next turn in a chat: each notice told there since, once.
  def untold_note(conversation)
    notices = CodeAgentSession::Notice.where(conversation_id: conversation.id).untold.includes(:session).order(:created_at).to_a
    return if notices.empty?

    CodeAgentSession::Notice.where(id: notices.map(&:id)).update_all(told_at: Time.current)
    lines = notices.map { |notice| "- #{notice.reason} #{notice.offer}" }
    "What happened to pull requests you opened, already told to the person with Fix it:\n#{lines.join("\n")}\n" \
      "This is yours to fix, with their yes. Never change the branch unless they press Fix it or ask you to."
  end
end
