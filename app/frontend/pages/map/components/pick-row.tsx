import type { ReactNode } from "react"

interface PickRowProps {
  resourceId: string
  onPick: (resourceId: string) => void
  tone?: "danger"
  children: ReactNode
}

export function PickRow({ resourceId, onPick, tone, children }: PickRowProps) {
  function pick() {
    onPick(resourceId)
  }

  return (
    <button
      type="button"
      onClick={pick}
      className={`flex flex-col gap-0.5 rounded-lg px-3 py-2 text-left text-sm transition-colors ${
        tone ? "border border-destructive/40 bg-destructive/10 hover:bg-destructive/15" : "hover:bg-muted/50"
      }`}
    >
      {children}
    </button>
  )
}
