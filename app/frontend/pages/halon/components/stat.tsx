import { Card } from "@/components/ui/card"

export function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <Card className="flex min-w-0 flex-col gap-1 px-4 py-3">
      <span className="text-[11px] font-medium tracking-[0.12em] text-fg-secondary uppercase">{label}</span>
      <span className="font-mono text-2xl font-semibold text-fg-primary tabular-nums">{value}</span>
      <span className="truncate text-xs text-fg-secondary">{note}</span>
    </Card>
  )
}
