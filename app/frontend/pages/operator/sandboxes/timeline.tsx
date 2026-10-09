import { TONE_CLASSES } from "@/components/investigations/tone"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { formatDateTime } from "@/lib/formatters"
import { FLAG_LABELS, PHASE_LABELS, boxTone, duration } from "@/pages/operator/lib/sandboxes"
import type { OperatorSandboxBox } from "@/types/serializers"

const LIMIT = 60
const HOURS = [0, 6, 12, 18, 24]

interface Lane {
  provider: string
  boxes: OperatorSandboxBox[]
}

function lanesOf(boxes: OperatorSandboxBox[], from: number): Lane[] {
  const shown = boxes.filter((box) => !box.endedAt || new Date(box.endedAt).getTime() >= from).slice(0, LIMIT)
  const lanes = new Map<string, OperatorSandboxBox[]>()
  shown.forEach((box) => {
    lanes.set(box.providerName, [...(lanes.get(box.providerName) ?? []), box])
  })
  return [...lanes.entries()].map(([provider, laneBoxes]) => ({ provider, boxes: laneBoxes }))
}

function hourLabel(from: number, hour: number): string {
  return new Date(from + hour * 3_600_000).toLocaleTimeString("en-US", { hour: "numeric" })
}

// Each box as a bar across the last 24 hours, one lane per provider, coloured by its worst flag, so a box that ran
// all day or has no record stands out at a glance.
export function SandboxTimeline({ boxes, windowStart, now }: { boxes: OperatorSandboxBox[]; windowStart: string; now: string }) {
  const from = new Date(windowStart).getTime()
  const to = new Date(now).getTime()
  const span = Math.max(to - from, 1)
  const lanes = lanesOf(boxes, from)

  function place(box: OperatorSandboxBox) {
    const start = Math.max(new Date(box.startedAt ?? now).getTime(), from)
    const end = box.endedAt ? new Date(box.endedAt).getTime() : to
    const left = ((start - from) / span) * 100
    const width = Math.max(((end - start) / span) * 100, 0.4)
    return { left: `${left}%`, width: `${Math.min(width, 100 - left)}%` }
  }

  if (lanes.length === 0) {
    return <p className="text-muted-foreground px-5 py-8 text-center text-sm">No box ran in the last 24 hours.</p>
  }

  return (
    <div className="flex flex-col gap-4 px-5 py-4">
      <div className="ml-[180px] flex justify-between text-[11px] text-muted-foreground">
        {HOURS.map((hour) => (
          <span key={hour}>{hour === 24 ? "Now" : hourLabel(from, hour)}</span>
        ))}
      </div>
      {lanes.map((lane) => (
        <div key={lane.provider} className="flex flex-col gap-1">
          <span className="text-[11px] font-medium tracking-[0.12em] text-muted-foreground uppercase">{lane.provider}</span>
          {lane.boxes.map((box) => (
            <div key={box.key} className="grid grid-cols-[172px_minmax(0,1fr)] items-center gap-2">
              <span className="truncate font-mono text-[12px]" title={box.name ?? box.ref}>
                {box.name ?? box.ref}
              </span>
              <div className="relative h-3.5 rounded-sm bg-surface-hover">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span className={`absolute top-0 h-full rounded-sm border ${TONE_CLASSES[boxTone(box)]}`} style={place(box)} />
                  </TooltipTrigger>
                  <TooltipContent>
                    {box.phase ? PHASE_LABELS[box.phase] : "Unknown"}
                    {box.flags.length > 0 && ` · ${box.flags.map((flag) => FLAG_LABELS[flag]).join(", ")}`}
                    {` · ${duration(box.seconds)}`}
                    {box.startedAt && ` · from ${formatDateTime(box.startedAt)}`}
                  </TooltipContent>
                </Tooltip>
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
