import type { ReactNode } from "react"

import { Card } from "@/components/ui/card"

export function SectionCard({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <Card className="gap-0 overflow-hidden py-0">
      <div className="flex items-baseline justify-between gap-4 border-b border-border px-5 py-4">
        <h2 className="text-sm font-semibold">{title}</h2>
        {note && <span className="text-muted-foreground text-xs">{note}</span>}
      </div>
      {children}
    </Card>
  )
}
