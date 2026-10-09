import { formatDate } from "@/lib/formatters"
import type { ResourceMapBaseline } from "@/types/serializers"

function latest(baselines: ResourceMapBaseline[]): string {
  const ends = baselines.map((baseline) => baseline.windowTo).sort()
  return ends[ends.length - 1] ?? ""
}

export function BaselinesTable({ baselines }: { baselines: ResourceMapBaseline[] }) {
  return (
    <div className="flex flex-col gap-1.5">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-[11px] text-muted-foreground">
            <th className="pb-1 font-normal" />
            <th className="pb-1 font-normal">Usually</th>
            <th className="pb-1 font-normal">95% under</th>
            <th className="pb-1 font-normal">Peak</th>
          </tr>
        </thead>
        <tbody className="tabular-nums">
          {baselines.map((baseline) => (
            <tr key={baseline.id} className="border-t border-border/60">
              <td className="py-1.5 pr-2">{baseline.label}</td>
              <td className="py-1.5 pr-2">{baseline.typical}</td>
              <td className="py-1.5 pr-2 text-muted-foreground">{baseline.high}</td>
              <td className="py-1.5 text-muted-foreground">{baseline.peak}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="text-xs text-muted-foreground">Read from the provider over the 7 days to {formatDate(latest(baselines))}.</p>
    </div>
  )
}
