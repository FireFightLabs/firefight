import { useState } from "react"
import { IconChevronRight } from "@tabler/icons-react"

// What a step took in or gave back, folded until opened, as pretty JSON that scrolls inside its frame.
export function JsonBlock({ label, value }: { label: string; value: unknown }) {
  const [open, setOpen] = useState(false)

  function toggle() {
    setOpen((current) => !current)
  }

  if (value === undefined || value === null) {
    return null
  }

  return (
    <div className="text-xs">
      <button type="button" onClick={toggle} className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground" aria-expanded={open}>
        <IconChevronRight className={`size-3.5 transition-transform ${open ? "rotate-90" : ""}`} />
        {label}
      </button>
      {open && (
        <pre className="mt-1 max-h-80 overflow-auto rounded-md border bg-muted/40 p-3 font-mono text-[11px] leading-relaxed">
          {JSON.stringify(value, null, 2)}
        </pre>
      )}
    </div>
  )
}
