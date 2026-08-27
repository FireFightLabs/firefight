import { Link } from "@inertiajs/react"

import type { AlertSettings } from "@/types/serializers"
import { incidentPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"

export function RoutingCell({ alert }: { alert: AlertSettings }) {
  if (alert.routingState === "routed") {
    if (alert.incidentId && alert.incidentIdentifier) {
      return (
        <Link href={incidentPath(alert.incidentId)} className="text-sm font-medium hover:underline">
          {alert.incidentIdentifier}
        </Link>
      )
    }
    return <Badge variant="outline">Routed</Badge>
  }
  if (alert.routingState === "unmatched") {
    return (
      <span className="text-xs text-amber-500/90" title="No routing rule matched this alert. It was stored but created nothing.">
        Unmatched
      </span>
    )
  }
  if (alert.routingState === "failed") {
    return (
      <span className="text-xs text-destructive" title="Routing failed repeatedly and gave up. Check the rule's outcome (e.g. severity) and the app logs.">
        Failed
      </span>
    )
  }
  return (
    <span className="text-xs text-muted-foreground/60" title="Routing has not completed yet. It is retried automatically every couple of minutes.">
      Pending
    </span>
  )
}
