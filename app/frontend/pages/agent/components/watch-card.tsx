import { router } from "@inertiajs/react"
import { type Icon, IconCheck, IconCircleDashed, IconEye, IconLoader2, IconMinus, IconX } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { WATCH_STATUSES, WATCH_STEP_STATUSES } from "@/lib/generated/constants"
import { agentChatWatchStopPath } from "@/lib/routes"
import { refreshWatches } from "@/pages/agent/lib/chat-updates"
import type { AgentChatWatch } from "@/types/serializers"

interface WatchCardProps {
  conversationId: string
  watch: AgentChatWatch
}

const STEP_ICONS: Record<string, { icon: Icon; className: string }> = {
  [WATCH_STEP_STATUSES.WAITING]: { icon: IconCircleDashed, className: "text-ink-3" },
  [WATCH_STEP_STATUSES.RUNNING]: { icon: IconLoader2, className: "text-ink-2 motion-safe:animate-spin" },
  [WATCH_STEP_STATUSES.SUCCEEDED]: { icon: IconCheck, className: "text-success" },
  [WATCH_STEP_STATUSES.FAILED]: { icon: IconX, className: "text-danger" },
  [WATCH_STEP_STATUSES.UNFOLLOWABLE]: { icon: IconMinus, className: "text-ink-3" },
}

// Something Halon keeps watching for this chat after its answer. While it goes it names what it follows, how long it
// watches and why, each step as it stands, and offers Stop. Once it ends it shows how. The server says whether this
// viewer may stop it, so the card decides nothing.
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
    router.post(agentChatWatchStopPath(conversationId, watch.id), {}, {
      preserveScroll: true, preserveState: true, onSuccess: refreshWatches, onFinish: doneStopping,
    })
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
        </div>
      </div>
      <ul className="flex flex-col gap-1.5">
        {watch.steps.map((step) => (
          <WatchStep key={step.id} label={step.label} status={step.status} state={step.state} />
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
        description={`Halon stops following ${watch.title} and says so here. It will not report on it again.`}
        confirmLabel="Stop watching"
        onConfirm={stop}
        onCancel={cancelStop}
      />
    </section>
  )
}

interface WatchStepProps {
  label: string
  status: string
  state: string | null
}

function WatchStep({ label, status, state }: WatchStepProps) {
  const mark = STEP_ICONS[status] ?? STEP_ICONS[WATCH_STEP_STATUSES.WAITING]
  const Mark = mark.icon
  return (
    <li className="flex items-start gap-2 text-[13px] leading-relaxed">
      <Mark className={`mt-1 size-3.5 shrink-0 ${mark.className}`} />
      <span className="min-w-0 [overflow-wrap:anywhere]">
        <span className="font-medium text-ink">{label}</span>
        {state && <span className="text-ink-2">. {state}</span>}
      </span>
    </li>
  )
}
