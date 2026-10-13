import { cn } from "@/lib/utils"
import type { WorkflowStepIcon } from "@/lib/generated/constants"
import { STEP_ICONS } from "@/pages/halon/lib/workflow/labels"

// A step's kind as a small tile, Halon's own steps in its violet.
export function StepIcon({ icon, halon = false, size = "md" }: { icon: WorkflowStepIcon; halon?: boolean; size?: "sm" | "md" }) {
  const Glyph = STEP_ICONS[icon]
  return (
    <span
      className={cn(
        "flex shrink-0 items-center justify-center rounded-md border",
        size === "md" ? "size-[30px]" : "size-6",
        halon ? "border-halon-border text-halon" : "border-border-strong text-brand",
      )}
    >
      <Glyph className={size === "md" ? "size-4" : "size-3.5"} stroke={1.7} />
    </span>
  )
}
