import { IconEye, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { WATCH_STATUSES } from "@/lib/generated/constants"
import { WatchStep } from "@/pages/agent/components/watch-step"
import { stopWatch } from "@/pages/agent/lib/chat-updates"
import type { AgentChatWatch } from "@/types/serializers"

interface WatchCardProps {
  conversationId: string
  watch: AgentChatWatch
}

// Something Halon keeps watching for this chat after its answer, named for what it waits on. While it goes it says how
// long it watches and why, its ceiling on reads, each step as it stands with the page of its run, and offers Stop. Once
// it ends it shows how. The server says whether this viewer may stop it, so the card decides nothing.
export function WatchCard({ conversationId, watch }: WatchCardProps) {
  const [ confirming, setConfirming ] = useState(false)
  const [ stopping, setStopping ] = useState(false)
  const active = watch.status === WATCH_STATUSES.ACTIVE

  function askToStop() {
    setConfirming(true)
  }

  function cancelStop() {
    setConfirming(false)
  }

  function stop() {
    setConfirming(false)
    setStopping(true)
    stopWatch(conversationId, watch.id, { onFinish: doneStopping })
  }

  function doneStopping() {
    setStopping(false)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Watch">
      <div className="flex items-start gap-2">
        <IconEye className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{watch.headline}</h3>
          {watch.purpose && <p className="text-[13px] leading-snug text-ink-2 [overflow-wrap:anywhere]">For: {watch.purpose}</p>}
          {watch.basis && <p className="text-[12.5px] text-ink-3">{watch.basis}</p>}
          <p className="text-[12.5px] text-ink-3">{watch.reads}</p>
        </div>
      </div>
      <ul className="flex flex-col gap-1.5">
        {watch.steps.map((step) => (
          <WatchStep key={step.id} label={step.label} status={step.status} state={step.state} url={step.url} />
        ))}
      </ul>
      {!active && watch.outcome && <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{watch.outcome}</p>}
      {active && (
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="secondary" disabled={watch.stopBlockedReason != null || stopping} onClick={askToStop}>
            {stopping && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Stop
          </Button>
          {watch.stopBlockedReason && <span className="text-[12.5px] text-ink-3">{watch.stopBlockedReason}</span>}
        </div>
      )}
      <ConfirmDeleteDialog
        open={confirming}
        title="Stop watching?"
        description={`Halon stops watching "${watch.title}" and says so here. It will not report on it again.`}
        confirmLabel="Stop watching"
        onConfirm={stop}
        onCancel={cancelStop}
      />
    </section>
  )
}
