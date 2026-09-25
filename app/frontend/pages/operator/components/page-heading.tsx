import type { ReactNode } from "react"

export function PageHeading({ title, lead, children }: { title: ReactNode; lead: string; children?: ReactNode }) {
  return (
    <div className="mb-7 flex items-end justify-between gap-6">
      <div className="flex max-w-3xl flex-col gap-2">
        <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
        <p className="text-sm leading-relaxed text-muted-foreground">{lead}</p>
      </div>
      {children && <div className="flex shrink-0 gap-2">{children}</div>}
    </div>
  )
}
