import * as React from "react"

import { cn } from "@/lib/utils"

// Native input so rows sharing a `name` form one keyboard-navigable group
// without a wrapper element, which a table body cannot host.
function Radio({ className, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      type="radio"
      data-slot="radio"
      className={cn(
        "size-4 shrink-0 cursor-pointer appearance-none rounded-full border border-input bg-input/30 shadow-xs transition-all outline-none",
        "checked:border-[5px] checked:border-primary checked:bg-background",
        "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
        "disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  )
}

export { Radio }
