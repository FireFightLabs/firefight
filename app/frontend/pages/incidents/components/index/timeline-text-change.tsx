import { useState } from "react"
import { IconChevronDown, IconChevronRight } from "@tabler/icons-react"
import type { TimelineChange } from "@/pages/incidents/types"

// Striking a paragraph beside its replacement reads badly, so the previous
// version waits behind a toggle.
export function TimelineTextChange({ change }: { change: TimelineChange }) {
  const [showingPrevious, setShowingPrevious] = useState(false)

  function togglePrevious() {
    setShowingPrevious(!showingPrevious)
  }

  const Chevron = showingPrevious ? IconChevronDown : IconChevronRight

  return (
    <div className="flex flex-col items-start gap-1.5">
      {change.after ? (
        <p className="text-sm leading-relaxed text-fg-primary whitespace-pre-line">{change.after}</p>
      ) : (
        <span className="text-sm italic text-fg-muted">Cleared</span>
      )}
      {change.before && (
        <button
          type="button"
          onClick={togglePrevious}
          className="inline-flex items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-fg-primary"
        >
          <Chevron className="size-3.5" />
          {showingPrevious ? "Hide previous version" : "Show previous version"}
        </button>
      )}
      {showingPrevious && change.before && (
        <p className="w-full rounded-md bg-background px-2.5 py-2 text-sm leading-relaxed text-fg-muted whitespace-pre-line">
          {change.before}
        </p>
      )}
    </div>
  )
}
