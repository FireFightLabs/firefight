import type { ResourceMapLogLevel } from "@/lib/generated/constants"
import type { ResourceMapLogTemplate } from "@/types/serializers"

const LEVEL_TONES: Record<ResourceMapLogLevel, string> = {
  error: "border-destructive/40 bg-destructive/10 text-destructive",
  warning: "border-warning/40 bg-warning-tint text-warning",
}

const LEVEL_LABELS: Record<ResourceMapLogLevel, string> = {
  error: "Error",
  warning: "Warning",
}

export function LogLine({ line }: { line: ResourceMapLogTemplate }) {
  return (
    <li className="flex flex-col gap-1 rounded-lg border border-border bg-background/50 px-3 py-2">
      <code className="font-mono text-[11.5px] leading-relaxed break-words">{line.template}</code>
      <span className="flex items-center gap-2 text-[11px] text-muted-foreground">
        {line.level && <span className={`rounded-full border px-1.5 py-px font-medium ${LEVEL_TONES[line.level]}`}>{LEVEL_LABELS[line.level]}</span>}
        <span>
          {line.lines} {line.lines === 1 ? "line" : "lines"} in the last read, seen in {line.samples} {line.samples === 1 ? "read" : "reads"}
        </span>
      </span>
    </li>
  )
}
