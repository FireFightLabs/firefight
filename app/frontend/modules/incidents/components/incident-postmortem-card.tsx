import { Link } from "@inertiajs/react"
import { IconArrowRight, IconFileText, IconFlame } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { incidentPostmortemPath } from "@/lib/routes"

export function IncidentPostmortemCard({
  incidentId,
  hasPostmortem,
}: {
  incidentId: string
  hasPostmortem: boolean
}) {
  if (hasPostmortem) {
    return (
      <Link href={incidentPostmortemPath(incidentId)}>
        <Card className="group cursor-pointer border-primary/20 bg-gradient-to-b from-primary/[0.04] to-transparent transition-all hover:border-primary/40">
          <CardContent className="flex items-center gap-3 py-4">
            <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10">
              <IconFileText className="size-4 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold">Postmortem</span>
                <Badge
                  variant="secondary"
                  className="text-[10px] bg-amber-500/15 text-amber-600 dark:text-amber-400"
                >
                  In progress
                </Badge>
              </div>
              <p className="mt-0.5 text-xs text-muted-foreground truncate">
                Root cause analysis and actions
              </p>
            </div>
            <IconArrowRight className="size-4 text-muted-foreground/30 transition-transform group-hover:translate-x-0.5 group-hover:text-primary" />
          </CardContent>
        </Card>
      </Link>
    )
  }

  return (
    <Card className="border-dashed">
      <CardContent className="flex flex-col items-center justify-center py-8 gap-3">
        <div className="flex size-10 items-center justify-center rounded-full bg-muted">
          <IconFileText className="size-5 text-muted-foreground" />
        </div>
        <div className="text-center">
          <p className="text-sm font-semibold">No postmortem</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Document what happened and prevent recurrence.
          </p>
        </div>
        <Button size="sm">
          <IconFlame className="size-4" />
          Generate
        </Button>
      </CardContent>
    </Card>
  )
}
