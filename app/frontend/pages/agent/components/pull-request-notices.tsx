import { PullRequestNoticeCard } from "@/pages/agent/components/pull-request-notice-card"
import type { AgentChatPullRequestNotice } from "@/types/serializers"

export function PullRequestNotices({ conversationId, notices }: { conversationId: string; notices: AgentChatPullRequestNotice[] | undefined }) {
  return notices?.map((notice) => <PullRequestNoticeCard key={notice.id} conversationId={conversationId} notice={notice} />)
}
