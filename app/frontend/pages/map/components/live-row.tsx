import { liveUpdatesLine } from "@/lib/live-updates"
import type { ResourceMapConnection } from "@/types/serializers"

export function LiveRow({ connection }: { connection: ResourceMapConnection }) {
  const state = connection.liveUpdates
  if (!state) {
    return null
  }

  return (
    <div className="flex gap-2.5 rounded-lg px-3 py-2 text-sm">
      <span className={`mt-1.5 size-1.5 shrink-0 rounded-full ${state.on ? "bg-success" : "bg-muted-foreground/50"}`} />
      <span className="flex flex-col gap-0.5">
        <span className="font-medium">{connection.name}</span>
        <span className="text-xs text-muted-foreground">{liveUpdatesLine(state)}</span>
        {state.reason && <span className="text-xs text-muted-foreground">{state.reason}</span>}
      </span>
    </div>
  )
}
