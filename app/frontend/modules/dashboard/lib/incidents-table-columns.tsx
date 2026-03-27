import { Link } from "@inertiajs/react"
import { type ColumnDef } from "@tanstack/react-table"

import type { IncidentListItem } from "@/types/serializers"
import { incidentPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { severityVariant, statusVariant } from "./constants"
import { formatDate, formatDuration } from "./formatters"
import { getStatusIcon } from "./status-display"

export const incidentsTableColumns: ColumnDef<IncidentListItem>[] = [
  {
    accessorKey: "identifier",
    header: "ID",
    cell: ({ row }) => (
      <span className="font-mono text-xs text-muted-foreground">
        {row.original.identifier}
      </span>
    ),
    enableHiding: false,
  },
  {
    accessorKey: "name",
    header: "Name",
    cell: ({ row }) => (
      <Link
        href={incidentPath(row.original.id)}
        className="font-medium text-foreground hover:underline"
      >
        {row.original.name}
      </Link>
    ),
    enableHiding: false,
  },
  {
    accessorKey: "severity",
    header: "Severity",
    cell: ({ row }) => (
      <Badge variant={severityVariant(row.original.severity.rank)}>
        {row.original.severity.name}
      </Badge>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => {
      const { name, lifecycleStage } = row.original.status
      return (
        <Badge variant={statusVariant(lifecycleStage)}>
          {getStatusIcon(name, lifecycleStage)}
          {name}
        </Badge>
      )
    },
  },
  {
    accessorKey: "lead",
    header: "Lead",
    cell: ({ row }) => (
      <span className="text-muted-foreground">
        {row.original.lead ?? "Unassigned"}
      </span>
    ),
  },
  {
    accessorKey: "declaredAt",
    header: "Declared",
    cell: ({ row }) => (
      <span className="text-muted-foreground">
        {formatDate(row.original.declaredAt)}
      </span>
    ),
  },
  {
    id: "duration",
    header: "Duration",
    cell: ({ row }) => (
      <span className="font-mono text-xs">
        {formatDuration(row.original.declaredAt, row.original.resolvedAt)}
      </span>
    ),
  },
]
