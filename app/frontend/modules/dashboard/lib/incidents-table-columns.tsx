import {
  IconCircleCheckFilled,
  IconCircleDashedCheck,
  IconLoader,
  IconUrgent,
} from "@tabler/icons-react"
import { Link } from "@inertiajs/react"
import { type ColumnDef } from "@tanstack/react-table"

import type { IncidentListItem } from "@/modules/incidents/types"
import { incidentPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { severityVariant, statusVariant } from "./constants"
import { formatDate, formatDuration } from "./formatters"

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
          {lifecycleStage === "closed" ? (
            <IconCircleCheckFilled className="fill-green-500 dark:fill-green-400" />
          ) : name === "Triage" ? (
            <IconUrgent className="size-3.5" />
          ) : name === "Monitoring" ? (
            <IconCircleDashedCheck className="size-3.5" />
          ) : (
            <IconLoader className="size-3.5" />
          )}
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
