import { IconBellRinging } from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
}

export function AlertsPanel({ alerts }: { alerts: Incident["alerts"] }) {
  if (alerts.length === 0) return null

  return (
    <div className="rounded-lg border border-border bg-card px-4 py-3.5">
      <div className="mb-3 flex items-baseline gap-2">
        <h3 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-foreground/90">Alerts</h3>
        <span className="text-[11px] tabular-nums text-muted-foreground/70">{alerts.length}</span>
      </div>
      <ul className="flex flex-col gap-2.5">
        {alerts.map((alert) => (
          <li key={alert.id} className="flex items-start gap-2.5">
            <span
              className={`mt-1 size-2 shrink-0 rounded-full ${alert.status === "firing" ? "bg-rose-400" : "bg-emerald-400"}`}
              aria-hidden
            />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13px] leading-snug text-foreground">{alert.title}</p>
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground/70">
                <IconBellRinging className="size-3" />
                {alert.sourceName}
                <span>·</span>
                fired {alert.eventCount}x
                <span>·</span>
                last {formatTime(alert.lastSeenAt)}
              </p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
