import { formatDateTime } from "@/lib/formatters"
import type { WorkspaceAiAccount } from "@/types/serializers"

type Subscription = NonNullable<WorkspaceAiAccount["subscription"]>

function limitLine(subscription: Subscription): string {
  if (subscription.reachedUntil) {
    return `At its usage limit until ${formatDateTime(subscription.reachedUntil)}.`
  }
  if (subscription.leftPercent === null) {
    return "This plan does not say how much of its limit is left."
  }
  const resets = subscription.resetsAt ? `, resets ${formatDateTime(subscription.resetsAt)}` : ""
  return `${subscription.leftPercent}% of its limit left${resets}.`
}

// How much of a subscription's usage limit is left and when it resets, as the subscription service last saw it.
export function SubscriptionLimit({ subscription }: { subscription: Subscription }) {
  return <p className="max-w-64 text-xs text-muted-foreground">{limitLine(subscription)}</p>
}
