import type { AlertSourceSettings } from "@/types/serializers"
import { formatDateTime } from "@/lib/formatters"

export function LastEventCell({ source }: { source: AlertSourceSettings }) {
  const { lastReceivedAt, lastRejectedAt } = source
  const received = lastReceivedAt ? Date.parse(lastReceivedAt) : 0
  const rejected = lastRejectedAt ? Date.parse(lastRejectedAt) : 0

  if (lastRejectedAt && rejected > received) {
    return (
      <span className="text-xs text-amber-500/90" title={`Last rejected ${formatDateTime(lastRejectedAt)}`}>
        Rejected: {source.lastRejectionReason}
      </span>
    )
  }
  if (lastReceivedAt && received > 0) {
    return <span className="text-xs text-muted-foreground">{formatDateTime(lastReceivedAt)}</span>
  }
  return <span className="text-xs text-muted-foreground/60">Never</span>
}
