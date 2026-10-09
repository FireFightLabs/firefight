import type { ReactNode } from "react"
import { IconTopologyStar3 } from "@tabler/icons-react"

export function EmptyState({ title, text, children }: { title: string; text: string; children?: ReactNode }) {
  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-4 px-4 py-24 text-center">
      <span className="flex size-12 items-center justify-center rounded-xl bg-muted">
        <IconTopologyStar3 className="size-6 text-muted-foreground" />
      </span>
      <h1 className="text-lg font-semibold">{title}</h1>
      <p className="text-sm text-muted-foreground">{text}</p>
      {children}
    </div>
  )
}
