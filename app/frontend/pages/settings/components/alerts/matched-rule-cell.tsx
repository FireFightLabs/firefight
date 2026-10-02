import { Link } from "@inertiajs/react"

import type { AlertSettings } from "@/types/serializers"
import { settingsAlertRoutingPath } from "@/lib/routes"

export function MatchedRuleCell({ alert }: { alert: AlertSettings }) {
  if (!alert.matchedRulePriority) {
    return <span className="text-xs text-fg-disabled">–</span>
  }

  const routingUrl = alert.matchedRuleSourceId
    ? settingsAlertRoutingPath({ source_id: alert.matchedRuleSourceId })
    : settingsAlertRoutingPath()

  return (
    <Link href={routingUrl} className="text-xs text-muted-foreground hover:text-foreground hover:underline">
      Rule {alert.matchedRulePriority}
      {!alert.matchedRuleSourceId && <span className="text-fg-muted"> (default)</span>}
    </Link>
  )
}
