import { IconInfoCircle } from "@tabler/icons-react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

// A column header that explains itself, for columns whose meaning is not
// obvious from the label alone.
export function HeaderHint({ label, hint }: { label: string; hint: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="inline-flex cursor-help items-center gap-1">
          {label}
          <IconInfoCircle className="size-3.5 text-muted-foreground/50" />
        </span>
      </TooltipTrigger>
      <TooltipContent side="top" className="max-w-64">{hint}</TooltipContent>
    </Tooltip>
  )
}
