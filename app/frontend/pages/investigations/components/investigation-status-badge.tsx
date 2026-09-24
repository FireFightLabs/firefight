import { Badge } from "@/components/ui/badge"
import type { InvestigationStatus } from "@/lib/generated/constants"
import { STATUS_LABELS, isKeyOf, labelFor } from "@/pages/investigations/lib/labels"

const VARIANTS: Record<InvestigationStatus, "default" | "secondary" | "outline"> = {
  pending: "secondary",
  running: "default",
  succeeded: "outline",
  failed: "secondary",
  canceled: "secondary",
}

export function InvestigationStatusBadge({ status }: { status: string }) {
  const variant = isKeyOf(VARIANTS, status) ? VARIANTS[status] : "secondary"
  return <Badge variant={variant}>{labelFor(STATUS_LABELS, status)}</Badge>
}
