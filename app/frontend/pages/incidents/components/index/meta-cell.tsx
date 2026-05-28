import type { ReactNode } from "react"

export function MetaCell({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <div className="px-5 py-3 min-w-0">
      <div className="text-[11px] font-medium uppercase tracking-[0.18em] text-muted-foreground/70">
        {label}
      </div>
      <div className="mt-1.5 text-sm text-foreground truncate">{children}</div>
    </div>
  )
}
