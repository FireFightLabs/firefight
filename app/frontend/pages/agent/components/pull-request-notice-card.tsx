import { IconExternalLink, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { PULL_REQUEST_NOTICE_STATUSES } from "@/lib/generated/constants"
import { NoticeMark } from "@/pages/agent/components/notice-mark"
import { fixPullRequest } from "@/pages/agent/lib/chat-updates"
import type { AgentChatPullRequestNotice } from "@/types/serializers"

interface PullRequestNoticeCardProps {
  conversationId: string
  notice: AgentChatPullRequestNotice
}

const ENDED_LINES: Partial<Record<AgentChatPullRequestNotice["status"], string>> = {
  [PULL_REQUEST_NOTICE_STATUSES.CLEARED]: "The code host no longer shows this.",
  [PULL_REQUEST_NOTICE_STATUSES.REPLACED]: "Something newer about this pull request is below.",
  [PULL_REQUEST_NOTICE_STATUSES.ENDED]: "The pull request was merged or closed, so Halon stopped following it.",
}

// A pull request Halon opened from this chat that needs attention: why, and what Fix it would do. Nothing on its branch
// changes until Fix it is pressed, and the server ships whether this person may press it.
export function PullRequestNoticeCard({ conversationId, notice }: PullRequestNoticeCardProps) {
  const [ sending, setSending ] = useState(false)
  const offered = notice.status === PULL_REQUEST_NOTICE_STATUSES.OFFERED
  const fixing = notice.status === PULL_REQUEST_NOTICE_STATUSES.FIXING

  function doneSending() {
    setSending(false)
  }

  function fix() {
    setSending(true)
    fixPullRequest(conversationId, notice.id, { onFinish: doneSending })
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Pull request needs attention">
      <div className="flex items-start gap-2">
        <NoticeMark status={notice.status} />
        <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{notice.headline}</h3>
      </div>
      <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{notice.reason}</p>
      {offered && <p className="text-[13px] leading-relaxed text-ink-2 [overflow-wrap:anywhere]">{notice.offer}</p>}
      {fixing && <p className="text-[12.5px] text-ink-3">Fix it pressed by {notice.fixedBy ?? "someone"}. Halon says how it went below.</p>}
      {ENDED_LINES[notice.status] && <p className="text-[12.5px] text-ink-3">{ENDED_LINES[notice.status]}</p>}
      <div className="flex flex-wrap items-center gap-2">
        {offered && (
          <Button size="sm" variant="primary" disabled={notice.fixBlockedReason != null || sending} onClick={fix}>
            {sending && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Fix it
          </Button>
        )}
        {notice.url && (
          <a href={notice.url} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-[12.5px] font-medium text-ink-2 hover:text-ink">
            <IconExternalLink className="size-3.5" />
            Open the pull request
          </a>
        )}
      </div>
      {offered && notice.fixBlockedReason && <p className="text-[12.5px] text-ink-3">{notice.fixBlockedReason}</p>}
    </section>
  )
}
