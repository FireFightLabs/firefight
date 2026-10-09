import type { ReactNode } from "react"

// One labelled part of an answer, such as its cause or how to fix it.
export function AnswerPart({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-1.5 sm:grid-cols-[8.5rem_1fr] sm:gap-4">
      <h3 className="pt-0.5 text-[11px] font-medium tracking-[0.15em] text-fg-muted uppercase">{label}</h3>
      <div className="min-w-0 text-sm leading-relaxed text-fg-body">{children}</div>
    </div>
  )
}
