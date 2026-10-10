import type { ReactNode } from "react"

// A titled part of the handbook's list, such as its pages or what waits for review.
export function PageListGroup({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-1">
      <h2 className="px-2 text-xs font-medium text-fg-muted">{title}</h2>
      <ul className="flex flex-col gap-0.5">{children}</ul>
    </section>
  )
}
