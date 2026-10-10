import { Link } from "@inertiajs/react"

import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { NOTICE_SEVERITIES } from "@/lib/generated/constants"
import { formatDate } from "@/lib/formatters"
import { investigationPath } from "@/lib/routes"
import { timeAgo } from "@/lib/time"
import type { InvestigationNotice } from "@/types/serializers"

function urgencyVariant(severity: string): "destructive" | "secondary" | "outline" {
  if (severity === NOTICE_SEVERITIES.HIGH) {
    return "destructive"
  }
  return severity === NOTICE_SEVERITIES.MEDIUM ? "secondary" : "outline"
}

function SaidCell({ notice }: { notice: InvestigationNotice }) {
  if (notice.unsaidReason) {
    return <span className="text-warning">{notice.unsaidReason}</span>
  }
  if (!notice.lastSaidAt) {
    return <span className="text-fg-muted">-</span>
  }

  const times = notice.timesSaid === 1 ? "once" : `${notice.timesSaid} times`
  return <span className="text-muted-foreground">{timeAgo(notice.lastSaidAt)}, {times}</span>
}

export function NoticesCard({ notices }: { notices: InvestigationNotice[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>What Halon raised</CardTitle>
        <CardDescription className="mt-1">
          Problems Halon found on its own, newest first. Each is said once and again only when it gets worse, so this is also what it stays quiet about.
        </CardDescription>
      </CardHeader>
      <CardContent className={notices.length === 0 ? undefined : "p-0"}>
        {notices.length === 0 ? (
          <p className="rounded-xl border border-dashed border-border px-6 py-8 text-center text-sm text-muted-foreground">
            Nothing yet. Problems from scheduled checks and leaked secrets show here once Halon finds them.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Problem</TableHead>
                <TableHead className="w-44">Urgency</TableHead>
                <TableHead className="hidden md:table-cell w-36">Becomes a problem</TableHead>
                <TableHead className="hidden lg:table-cell">Said</TableHead>
                <TableHead className="w-24" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {notices.map((notice) => (
                <TableRow key={notice.id}>
                  <TableCell className="whitespace-normal">
                    <div className="font-medium">{notice.signalLabel}: {notice.topic}</div>
                    <div className="mt-0.5 text-xs text-muted-foreground">{notice.summary}</div>
                    {notice.checkName && <div className="mt-0.5 text-xs text-fg-muted">From {notice.checkName}</div>}
                  </TableCell>
                  <TableCell>
                    <Badge variant={urgencyVariant(notice.severity)}>{notice.severityLabel}</Badge>
                  </TableCell>
                  <TableCell className="hidden md:table-cell text-sm text-muted-foreground">
                    {notice.dueOn ? formatDate(`${notice.dueOn}T00:00:00`) : "-"}
                  </TableCell>
                  <TableCell className="hidden lg:table-cell max-w-64 whitespace-normal text-sm"><SaidCell notice={notice} /></TableCell>
                  <TableCell>
                    {notice.investigationId && (
                      <Link href={investigationPath(notice.investigationId)} className="text-sm text-link hover:underline">
                        Open run
                      </Link>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
