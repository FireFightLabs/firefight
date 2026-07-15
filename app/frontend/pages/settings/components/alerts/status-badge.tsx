import { Badge } from "@/components/ui/badge"

export function StatusBadge({ status }: { status: string }) {
  if (status === "firing") return <Badge variant="destructive">Firing</Badge>
  return <Badge variant="secondary">Resolved</Badge>
}
