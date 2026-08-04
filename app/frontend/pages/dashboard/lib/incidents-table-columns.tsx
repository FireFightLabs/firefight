import { Link } from "@inertiajs/react"
import { type ColumnDef } from "@tanstack/react-table"

import type { IncidentListItem } from "@/types/serializers"
import { incidentPath } from "@/lib/routes"
import { severityBadgeStyle } from "@/lib/severity-color"
import { formatDateTime, formatDuration } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import { StatusIcon } from "@/pages/dashboard/components/status-icon"

export const incidentsTableColumns: ColumnDef<IncidentListItem>[] = [
  {
    accessorKey: "identifier",
    header: "ID",
    cell: ({ row }) => (
      <span className="font-mono text-sm text-foreground/60">
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
        prefetch="hover"
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
      <Badge className="min-w-24 justify-center py-1" style={severityBadgeStyle(row.original.severity.color)}>
        {row.original.severity.name}
      </Badge>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => {
      const { name, color, lifecycleStage } = row.original.status
      return (
        <Badge
          style={{
            backgroundColor: `${color}33`,
            color: color,
            borderColor: `${color}66`,
            minWidth: "7.5rem",
            paddingTop: "0.25rem",
            paddingBottom: "0.25rem",
          }}
        >
          <StatusIcon statusName={name} lifecycleStage={lifecycleStage} />
          {name}
        </Badge>
      )
    },
  },
  {
    accessorKey: "lead",
    header: "Lead",
    cell: ({ row }) => (
      row.original.lead
        ? <span>{row.original.lead}</span>
        : <span className="text-muted-foreground">Unassigned</span>
    ),
  },
  {
    accessorKey: "declaredBy",
    header: "Declared by",
    cell: ({ row }) => (
      row.original.declaredBy
        ? <span>{row.original.declaredBy}</span>
        : <span className="text-muted-foreground">-</span>
    ),
  },
  {
    accessorKey: "declaredAt",
    header: "Declared",
    cell: ({ row }) => (
      <span className="text-muted-foreground">
        {formatDateTime(row.original.declaredAt)}
      </span>
    ),
  },
  {
    id: "duration",
    header: "Duration",
    cell: ({ row }) => (
      <span className="font-mono text-sm text-foreground/60">
        {formatDuration(row.original.declaredAt, row.original.resolvedAt)}
      </span>
    ),
  },
]
