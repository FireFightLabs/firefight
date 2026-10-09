import { IconLoader2, IconLock } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { askAdminForPack } from "@/pages/agent/lib/chat-updates"
import type { AgentChatPackRefusal } from "@/types/serializers"

interface PackRefusalCardProps {
  conversationId: string
  refusal: AgentChatPackRefusal
}

// A change Halon was refused because the person holds no pack for it. It names the pack and the admins, and Ask an
// admin sends them one request. The server says who may ask and when it was asked, so the card decides nothing.
export function PackRefusalCard({ conversationId, refusal }: PackRefusalCardProps) {
  const [ sending, setSending ] = useState(false)

  function ask() {
    setSending(true)
    askAdminForPack(conversationId, refusal.id, { onFinish: stopSending })
  }

  function stopSending() {
    setSending(false)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Change refused">
      <div className="flex items-start gap-2">
        <IconLock className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink">{refusal.headline}</h3>
          <p className="text-[13px] leading-relaxed text-ink-2">{refusal.body}</p>
        </div>
      </div>
      {refusal.askedLine ? (
        <p className="text-[12.5px] text-ink-3">{refusal.askedLine}</p>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="primary" disabled={refusal.askBlockedReason != null || sending} onClick={ask}>
            {sending && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Ask an admin
          </Button>
          {refusal.askBlockedReason && <span className="text-[12.5px] text-ink-3">{refusal.askBlockedReason}</span>}
        </div>
      )}
    </section>
  )
}
