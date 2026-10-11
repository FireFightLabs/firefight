import { IconChevronDown, IconEye, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { useElapsed } from "@/hooks/use-elapsed"
import { WATCH_STATUSES } from "@/lib/generated/constants"
import { WatchStep } from "@/pages/agent/components/watch-step"
import { WatchUpdate } from "@/pages/agent/components/watch-update"
import { stopWatch } from "@/pages/agent/lib/chat-updates"
import { watchDuration } from "@/pages/agent/lib/watch"
import type { AgentChatWatch } from "@/types/serializers"

interface WatchCardProps {
  conversationId: string
  watch: AgentChatWatch
}

// One live card per watch, which moves in place as the watch reads rather than adding a line to the chat each time. Its
// header names it with how it stands and how long it has gone, each step is one row saying where it stands in a few words
// with the page of its run, and Details holds why it watches as long as it does, its ceiling on reads and everything it
// said. While it goes it offers Stop. The server says whether this viewer may stop it, so the card decides nothing.
export function WatchCard({ conversationId, watch }: WatchCardProps) {
  const [ confirming, setConfirming ] = useState(false)
  const [ stopping, setStopping ] = useState(false)
  const [ detailsOpen, setDetailsOpen ] = useState(false)
  const active = watch.status === WATCH_STATUSES.ACTIVE
  const elapsed = useElapsed(watch.at, watch.finishedAt ?? null, active)

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

  function toggleDetails() {
    setDetailsOpen((open) => !open)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Watch">
      <div className="flex items-start gap-2">
        <IconEye className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
            <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{watch.headline}</h3>
            <span className="shrink-0 text-[12.5px] tabular-nums text-ink-3">
              {active ? `${watchDuration(elapsed)} so far` : `Ran ${watchDuration(elapsed)}`}
            </span>
          </div>
          {watch.purpose && <p className="text-[13px] leading-snug text-ink-2 [overflow-wrap:anywhere]">For: {watch.purpose}</p>}
        </div>
      </div>
      <ul className="flex flex-col gap-1.5">
        {watch.steps.map((step) => (
          <WatchStep key={step.id} label={step.label} status={step.status} line={step.line} url={step.url} />
        ))}
      </ul>
      <div className="flex flex-wrap items-center gap-2">
        {active && (
          <Button size="sm" variant="secondary" disabled={watch.stopBlockedReason != null || stopping} onClick={askToStop}>
            {stopping && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
            Stop
          </Button>
        )}
        <button
          type="button"
          aria-expanded={detailsOpen}
          onClick={toggleDetails}
          className="-mx-1.5 flex items-center gap-1 rounded-control px-1.5 py-1 text-[12.5px] text-ink-2 transition-colors duration-150 hover:bg-hover-2 hover:text-ink"
        >
          Details
          <IconChevronDown className={`size-3.5 transition-transform duration-150 ${detailsOpen ? "rotate-180" : ""}`} />
        </button>
        {active && watch.stopBlockedReason && <span className="text-[12.5px] text-ink-3">{watch.stopBlockedReason}</span>}
      </div>
      {detailsOpen && (
        <div className="flex flex-col gap-2.5 border-t border-line pt-3">
          {watch.basis && <p className="text-[12.5px] text-ink-3">{watch.basis}</p>}
          <p className="text-[12.5px] text-ink-3">{watch.reads}</p>
          {watch.history.length === 0 ? (
            <p className="text-[12.5px] text-ink-3">Nothing said yet.</p>
          ) : (
            <ol className="flex flex-col gap-2" aria-label="Everything the watch said">
              {watch.history.map((update) => (
                <li key={update.id}>
                  <WatchUpdate update={update} compact />
                </li>
              ))}
            </ol>
          )}
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
