import type { ReactNode } from "react"

// The small heading that carries an answer card's state.
export function AnswerHeading({ children }: { children: ReactNode }) {
  return <div className="flex items-center gap-2 text-[11px] font-semibold tracking-[0.18em] uppercase">{children}</div>
}
