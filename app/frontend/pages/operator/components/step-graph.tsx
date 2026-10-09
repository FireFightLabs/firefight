import { IconCheck, IconClock, IconX, type Icon } from "@tabler/icons-react"

import { OPERATOR_STEP_STATUSES } from "@/pages/operator/generated/constants"
import { STEP_STATUS_TONES, TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorWorkflow } from "@/types/serializers"

type Step = OperatorWorkflow["steps"][number]

const NODE_WIDTH = 200
const NODE_HEIGHT = 52
const COLUMN_GAP = 44
const ROW_GAP = 18

function statusIcon(status: Step["status"]): Icon {
  if (status === OPERATOR_STEP_STATUSES.SUCCEEDED) {
    return IconCheck
  }
  if (status === OPERATOR_STEP_STATUSES.FAILED) {
    return IconX
  }
  return IconClock
}

function place(step: Step) {
  return { left: step.column * (NODE_WIDTH + COLUMN_GAP), top: step.row * (NODE_HEIGHT + ROW_GAP) }
}

// An edge from each step to every step it waits for. Edges into a failed step are drawn in the error colour.
export function StepGraph({ steps, selected, onSelect }: { steps: Step[]; selected: string | null; onSelect: (id: string) => void }) {
  const byName = new Map(steps.map((step) => [step.name, step]))
  const width = (Math.max(0, ...steps.map((step) => step.column)) + 1) * (NODE_WIDTH + COLUMN_GAP)
  const height = (Math.max(0, ...steps.map((step) => step.row)) + 1) * (NODE_HEIGHT + ROW_GAP)
  const edges = steps.flatMap((step) =>
    step.dependsOn.flatMap((name) => {
      const from = byName.get(name)
      if (!from) {
        return []
      }
      const start = place(from)
      const end = place(step)
      const x1 = start.left + NODE_WIDTH
      const y1 = start.top + NODE_HEIGHT / 2
      const x2 = end.left
      const y2 = end.top + NODE_HEIGHT / 2
      const middle = (x1 + x2) / 2
      return [{ key: `${name}-${step.name}`, path: `M${x1} ${y1} C${middle} ${y1}, ${middle} ${y2}, ${x2} ${y2}`, failed: step.status === OPERATOR_STEP_STATUSES.FAILED }]
    }),
  )

  return (
    <div className="overflow-x-auto">
      <div className="relative" style={{ width, height }}>
        <svg width={width} height={height} className="absolute inset-0" aria-hidden>
          {edges.map((edge) => (
            <path key={edge.key} d={edge.path} fill="none" strokeWidth={1.5} className={edge.failed ? "stroke-error/60" : "stroke-border-control"} />
          ))}
        </svg>
        {steps.map((step) => {
          const StatusIcon = statusIcon(step.status)
          const position = place(step)
          return (
            <button
              key={step.id}
              type="button"
              onClick={() => onSelect(step.id)}
              aria-pressed={selected === step.id}
              className={`absolute flex flex-col justify-center gap-0.5 rounded-lg border px-3 text-left transition-shadow ${TONE_CLASSES[STEP_STATUS_TONES[step.status]]} ${selected === step.id ? "ring-2 ring-brand" : ""}`}
              style={{ ...position, width: NODE_WIDTH, height: NODE_HEIGHT }}
            >
              <span className="flex items-center gap-1.5 font-mono text-xs font-medium text-foreground">
                <StatusIcon className="size-3.5 shrink-0" stroke={2} />
                <span className="truncate">{step.name}</span>
              </span>
              <span className="text-[11px] opacity-80">
                {step.status}
                {step.seconds != null && ` · ${step.seconds} s`}
                {step.attempts > 1 && ` · ${step.attempts} tries`}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
