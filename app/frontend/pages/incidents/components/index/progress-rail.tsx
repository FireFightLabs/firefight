export function ProgressRail({ done, total }: { done: number; total: number }) {
  const pct = total > 0 ? (done / total) * 100 : 0
  const complete = total > 0 && done === total
  return (
    <div className="flex items-center gap-3">
      <div className="h-1 flex-1 rounded-full bg-muted overflow-hidden">
        <div
          className="h-full rounded-full bg-brand transition-all duration-700 ease-out"
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="font-mono text-[11px] tabular-nums text-fg-secondary">
        {done}/{total}
      </span>
    </div>
  )
}
