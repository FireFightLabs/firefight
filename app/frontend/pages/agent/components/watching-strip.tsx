import { IconChevronDown, IconEye, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { useElapsed } from "@/hooks/use-elapsed"
import { WATCH_STATUSES } from "@/lib/generated/constants"
import { WatchCard } from "@/pages/agent/components/watch-card"
import { watchDuration } from "@/pages/agent/lib/watch"
import type { AgentChatWatch } from "@/types/serializers"

interface WatchingStripProps {
  conversationId: string
  watches: AgentChatWatch[]
}

// The watches going in this chat, pinned above the message box so they stay in sight however far the chat scrolls. Each
// row names one with where it stands and how long it has gone, and opens to its live card. It is gone once none are going.
export function WatchingStrip({ conversationId, watches }: WatchingStripProps) {
  const [ openId, setOpenId ] = useState<string | null>(null)
  const going = watches.filter((watch) => watch.status === WATCH_STATUSES.ACTIVE)
  if (going.length === 0) {
    return null
  }

  function toggle(watchId: string) {
    setOpenId((current) => (current === watchId ? null : watchId))
  }

  return (
    <section aria-label="Watching" className="mx-auto mb-2 w-full max-w-3xl overflow-hidden rounded-card bg-surface shadow-card">
      <h2 className="flex items-center gap-1.5 px-3 pt-2 pb-1 text-[12px] font-medium text-ink-3">
        <IconEye className="size-3.5" />
        Watching
      </h2>
      <ul className="flex flex-col divide-y divide-line">
        {going.map((watch) => (
          <WatchingRow
            key={watch.id}
            conversationId={conversationId}
            watch={watch}
            open={openId === watch.id}
            onToggle={toggle}
          />
        ))}
      </ul>
    </section>
  )
}

interface WatchingRowProps {
  conversationId: string
  watch: AgentChatWatch
  open: boolean
  onToggle: (watchId: string) => void
}

function WatchingRow({ conversationId, watch, open, onToggle }: WatchingRowProps) {
  const elapsed = useElapsed(watch.at, null, true)

  function toggle() {
    onToggle(watch.id)
  }

  return (
    <li>
      <button
        type="button"
        aria-expanded={open}
        onClick={toggle}
        className="flex w-full items-center gap-2.5 px-3 py-2 text-left transition-colors duration-150 hover:bg-hover"
      >
        <IconLoader2 className="size-3.5 shrink-0 text-ink-2 motion-safe:animate-spin" aria-hidden />
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-[13px] font-medium text-ink">{watch.title}</span>
          {watch.standing && <span className="truncate text-[12.5px] text-ink-3">{watch.standing}</span>}
        </span>
        <span className="shrink-0 text-[12.5px] tabular-nums text-ink-3">{watchDuration(elapsed)}</span>
        <IconChevronDown className={`size-3.5 shrink-0 text-ink-3 transition-transform duration-150 ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="max-h-[45dvh] overflow-y-auto border-t border-line">
          <WatchCard conversationId={conversationId} watch={watch} embedded />
        </div>
      )}
    </li>
  )
}
