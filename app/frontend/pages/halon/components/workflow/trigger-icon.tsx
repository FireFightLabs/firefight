import { cn } from "@/lib/utils"
import type { WorkflowTriggerIcon } from "@/lib/generated/constants"
import { TRIGGER_ICONS } from "@/pages/halon/lib/workflow/labels"

// A trigger's kind as a small tile, in the brand colour a run starts from.
export function TriggerIcon({ icon, size = "md" }: { icon: WorkflowTriggerIcon; size?: "sm" | "md" }) {
  const Glyph = TRIGGER_ICONS[icon]
  return (
    <span className={cn("flex shrink-0 items-center justify-center rounded-md border border-brand-border bg-brand-tint text-brand", size === "md" ? "size-[30px]" : "size-6")}>
      <Glyph className={size === "md" ? "size-4" : "size-3.5"} stroke={1.7} />
    </span>
  )
}
