import { Link, router } from "@inertiajs/react"

import { TablePagination } from "@/components/table-pagination"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { INVESTIGATION_PROPS } from "@/lib/generated/constants"
import { investigationPath, investigationsPath } from "@/lib/routes"
import { InvestigationStatusBadge } from "@/pages/investigations/components/investigation-status-badge"
import { formatSeconds, formatSpend } from "@/pages/investigations/lib/format"
import type { IncidentFilter } from "@/pages/investigations/types"
import type { Pagination } from "@/types"
import type { InvestigationListItem } from "@/types/serializers"

const PAGE_SIZES = [10, 25, 50]

interface InvestigationsTableProps {
  investigations: InvestigationListItem[]
  pagination: Pagination
  incident: IncidentFilter | null
}

export function InvestigationsTable({ investigations, pagination, incident }: InvestigationsTableProps) {
  function visit(page: number, perPage: number) {
    router.get(
      investigationsPath(),
      { page, per_page: perPage, incident_id: incident?.id },
      { preserveScroll: true, only: [INVESTIGATION_PROPS.INVESTIGATIONS, INVESTIGATION_PROPS.PAGINATION] },
    )
  }

  function changePage(page: number) {
    visit(page, pagination.perPage)
  }

  function changePerPage(perPage: number) {
    visit(1, perPage)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{incident ? `${incident.identifier} investigations` : "Investigations"}</CardTitle>
        <CardDescription>
          {incident ? (
            <>
              Every run on {incident.name}.{" "}
              <Link href={investigationsPath()} className="text-foreground hover:underline">
                Show all investigations
              </Link>
            </>
          ) : (
            "Every run Halon made to find what caused an incident, what it found and what it spent."
          )}
        </CardDescription>
      </CardHeader>
      {investigations.length > 0 ? (
        <CardContent className="flex flex-col gap-4 p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Incident</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Answer</TableHead>
                <TableHead>Asked by</TableHead>
                <TableHead>Started</TableHead>
                <TableHead className="text-right">Took</TableHead>
                <TableHead className="text-right">Spent</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {investigations.map((investigation) => (
                <TableRow key={investigation.id}>
                  <TableCell className="whitespace-nowrap font-medium">
                    <Link href={investigationPath(investigation.id)} className="hover:underline">
                      {investigation.incidentIdentifier ?? "Investigation"}
                    </Link>
                    {investigation.incidentName && (
                      <span className="text-muted-foreground block max-w-56 truncate text-xs">{investigation.incidentName}</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <InvestigationStatusBadge status={investigation.status} />
                  </TableCell>
                  <TableCell className="text-muted-foreground min-w-64 max-w-md whitespace-normal">
                    <span className="line-clamp-2">{investigation.answer ?? "-"}</span>
                  </TableCell>
                  <TableCell className="text-muted-foreground whitespace-nowrap">{investigation.askedBy ?? "-"}</TableCell>
                  <TableCell className="text-muted-foreground whitespace-nowrap">{formatDateTime(investigation.createdAt)}</TableCell>
                  <TableCell className="text-muted-foreground text-right">{formatSeconds(investigation.durationSeconds)}</TableCell>
                  <TableCell className="text-muted-foreground text-right">{formatSpend(investigation.spentCents)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <div className="px-4 pb-4">
            <TablePagination pagination={pagination} onPageChange={changePage} onPerPageChange={changePerPage} totalLabel={`${pagination.totalCount === 1 ? "investigation" : "investigations"} total`} pageSizeOptions={PAGE_SIZES} />
          </div>
        </CardContent>
      ) : (
        <CardContent>
          <p className="text-muted-foreground py-8 text-center text-sm">
            No investigations yet. Start one with /ff investigate in an incident channel, or ask Halon in a chat.
          </p>
        </CardContent>
      )}
    </Card>
  )
}
