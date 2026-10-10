import type { Tone } from "@/components/investigations/tone"
import { OPERATOR_SANDBOX_FLAGS, OPERATOR_SANDBOX_PHASES } from "@/pages/operator/generated/constants"
import type { OperatorSandboxBox } from "@/types/serializers"

type Flag = OperatorSandboxBox["flags"][number]
type Phase = NonNullable<OperatorSandboxBox["phase"]>

export const FLAG_LABELS: Record<Flag, string> = {
  [OPERATOR_SANDBOX_FLAGS.ROGUE]: "No record",
  [OPERATOR_SANDBOX_FLAGS.OVERDUE]: "Overdue",
  [OPERATOR_SANDBOX_FLAGS.FAILED]: "Failed",
  [OPERATOR_SANDBOX_FLAGS.STUCK]: "Stuck",
  [OPERATOR_SANDBOX_FLAGS.MISSING]: "Gone at provider",
}

export const FLAG_TONES: Record<Flag, Tone> = {
  [OPERATOR_SANDBOX_FLAGS.ROGUE]: "error",
  [OPERATOR_SANDBOX_FLAGS.OVERDUE]: "warning",
  [OPERATOR_SANDBOX_FLAGS.FAILED]: "error",
  [OPERATOR_SANDBOX_FLAGS.STUCK]: "warning",
  [OPERATOR_SANDBOX_FLAGS.MISSING]: "warning",
}

export const PHASE_LABELS: Record<Phase, string> = {
  [OPERATOR_SANDBOX_PHASES.STARTING]: "Starting",
  [OPERATOR_SANDBOX_PHASES.RUNNING]: "Running",
  [OPERATOR_SANDBOX_PHASES.STOPPING]: "Stopping",
  [OPERATOR_SANDBOX_PHASES.STOPPED]: "Stopped",
  [OPERATOR_SANDBOX_PHASES.READY]: "Ready",
  [OPERATOR_SANDBOX_PHASES.FAILED]: "Failed",
}

const ACTIVE: Phase[] = [OPERATOR_SANDBOX_PHASES.STARTING, OPERATOR_SANDBOX_PHASES.RUNNING, OPERATOR_SANDBOX_PHASES.STOPPING]

export function isActive(phase: OperatorSandboxBox["phase"]): boolean {
  return phase !== null && phase !== undefined && ACTIVE.includes(phase)
}

// The worst flag decides a box's colour, then whether it still runs.
export function boxTone(box: OperatorSandboxBox): Tone {
  const flagged = box.flags.map((flag) => FLAG_TONES[flag])
  if (flagged.includes("error")) {
    return "error"
  }
  if (flagged.includes("warning")) {
    return "warning"
  }
  return isActive(box.phase) ? "active" : "neutral"
}

export function bytes(size: number | null | undefined): string {
  if (size === null || size === undefined) {
    return "-"
  }
  const units = ["B", "KB", "MB", "GB", "TB"]
  let value = size
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`
}

// How long a box ran, in hours and minutes once it ran an hour.
export function duration(total: number): string {
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  if (hours > 0) {
    return `${hours}h ${String(minutes).padStart(2, "0")}m`
  }
  return minutes > 0 ? `${minutes}m` : `${total}s`
}
