import { Link } from "@inertiajs/react"
import { IconArrowRight, type Icon } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { Card } from "@/components/ui/card"

interface PanelProps {
  title: string
  icon: Icon
  href: string
  source: string
  external?: boolean
  children: ReactNode
}

export function OverviewPanel({ title, icon: PanelIcon, href, source, external, children }: PanelProps) {
  const view = (
    <>
      View
      <IconArrowRight className="size-3.5" />
    </>
  )
  const viewClass = "text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-xs"

  return (
    <Card className="gap-4 px-5 py-5">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <PanelIcon className="text-fg-secondary size-4" stroke={1.7} />
          {title}
        </h2>
        {external ? <a href={href} className={viewClass}>{view}</a> : <Link href={href} className={viewClass}>{view}</Link>}
      </div>
      <div className="grid grid-cols-2 gap-3">{children}</div>
      <p className="text-fg-muted text-xs">{source}</p>
    </Card>
  )
}
