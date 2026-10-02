import type { ReactNode } from "react"

export function MetaCell({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <div className="min-w-0">
      <div className="text-[11px] font-medium uppercase tracking-[0.18em] text-fg-muted">
        {label}
      </div>
      <div className="mt-1.5 text-sm text-fg-primary truncate">{children}</div>
    </div>
  )
}
