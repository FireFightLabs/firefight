import { Line } from "@/components/code-fix/line"
import type { CodeFixLine } from "@/lib/code-fix-work"

// The newest lines, keyed by their place among every line the agent wrote, so a line keeps its key as older ones drop.
export function Lines({ lines, total, current }: { lines: CodeFixLine[]; total: number; current: boolean }) {
  const first = total - lines.length
  return (
    <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
      {lines.map((line, index) => (
        <Line key={first + index} line={line} current={current && index === lines.length - 1} />
      ))}
    </ul>
  )
}
