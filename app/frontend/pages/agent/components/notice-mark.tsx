import { IconAlertTriangle, IconCheck, IconCornerUpLeft, IconTool } from "@tabler/icons-react"

import { PULL_REQUEST_NOTICE_STATUSES } from "@/lib/generated/constants"
import type { AgentChatPullRequestNotice } from "@/types/serializers"

export function NoticeMark({ status }: { status: AgentChatPullRequestNotice["status"] }) {
  if (status === PULL_REQUEST_NOTICE_STATUSES.FIXING) {
    return <IconTool className="mt-0.5 size-4 shrink-0 text-ink-2" />
  }
  if (status === PULL_REQUEST_NOTICE_STATUSES.CLEARED) {
    return <IconCheck className="mt-0.5 size-4 shrink-0 text-success" />
  }
  if (status === PULL_REQUEST_NOTICE_STATUSES.OFFERED) {
    return <IconAlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
  }
  return <IconCornerUpLeft className="mt-0.5 size-4 shrink-0 text-ink-3" />
}
