import { useRef, useState, type MouseEvent, type PointerEvent, type ReactNode } from "react"

import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

const MOUSE = "mouse"

// A disabled control swallows pointer events, so the tooltip rides on a span.
// Children render bare when there is no reason. A tooltip opens on hover, which a touch screen has none of, so a tap
// on the span opens it there too, and a tap anywhere else closes it.
export function Blocked({
  reason,
  side = "left",
  className = "inline-block",
  children,
}: {
  reason?: string
  side?: "top" | "right" | "bottom" | "left"
  // The span the tooltip rides on, block when the control fills its column.
  className?: string
  children: ReactNode
}) {
  const [ open, setOpen ] = useState(false)
  const tapping = useRef(false)

  // The trigger closes its tooltip on any press, so a tap keeps that from happening before it opens it.
  function tapped(event: PointerEvent<HTMLSpanElement>) {
    tapping.current = event.pointerType !== MOUSE
    if (!tapping.current) {
      return
    }
    event.preventDefault()
    setOpen(true)
  }

  // The trigger closes its tooltip on click too, and a tap ends in one, so the click that follows a tap is kept from it.
  function clicked(event: MouseEvent<HTMLSpanElement>) {
    if (!tapping.current) {
      return
    }
    tapping.current = false
    event.preventDefault()
  }

  if (!reason) {
    return children
  }

  return (
    <Tooltip open={open} onOpenChange={setOpen}>
      <TooltipTrigger asChild>
        <span className={className} onPointerDown={tapped} onClick={clicked}>{children}</span>
      </TooltipTrigger>
      <TooltipContent side={side} className="max-w-56">{reason}</TooltipContent>
    </Tooltip>
  )
}
