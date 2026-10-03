import { Link } from "@inertiajs/react"
import { type ColumnDef } from "@tanstack/react-table"

import type { IncidentListItem } from "@/types/serializers"
import { incidentPath } from "@/lib/routes"
import { SeverityBadge } from "@/components/severity-badge"
import { StatusBadge } from "@/components/status-badge"
import { formatDateTime, formatDuration } from "@/lib/formatters"

export const incidentsTableColumns: ColumnDef<IncidentListItem>[] = [
  {
    accessorKey: "identifier",
    header: "ID",
    cell: ({ row }) => (
      <Link
        href={incidentPath(row.original.id)}
        prefetch="hover"
        className="font-mono text-sm text-fg-muted transition-colors duration-120 hover:text-fg-primary hover:underline"
      >
        {row.original.identifier}
      </Link>
    ),
    enableHiding: false,
  },
  {
    accessorKey: "name",
    header: "Name",
    cell: ({ row }) => (
      <span className="inline-flex items-center gap-2">
        <Link
          href={incidentPath(row.original.id)}
          prefetch="hover"
          className={row.original.name ? "font-medium text-fg-primary hover:underline" : "italic text-fg-muted hover:underline"}
        >
          {row.original.name || "Untitled"}
        </Link>
        {row.original.isTest && (
          <span
            className="inline-flex items-center rounded-full border border-dashed border-border px-2 py-0.5 text-[10px] font-medium text-muted-foreground"
            title="Test incident. Not counted in your metrics."
          >
            Test
          </span>
        )}
      </span>
    ),
    enableHiding: false,
  },
  {
    accessorKey: "severity",
    header: "Severity",
    cell: ({ row }) => <SeverityBadge severity={row.original.severity} />,
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
  {
    accessorKey: "lead",
    header: "Lead",
    cell: ({ row }) => (
      row.original.lead
        ? <span className="text-fg-body">{row.original.lead}</span>
        : <span className="text-fg-muted">Unassigned</span>
    ),
  },
  {
    accessorKey: "declaredBy",
    header: "Declared by",
    cell: ({ row }) => (
      row.original.declaredBy
        ? <span className="text-fg-body">{row.original.declaredBy}</span>
        : <span className="text-fg-muted">-</span>
    ),
  },
  {
    accessorKey: "declaredAt",
    header: "Declared",
    cell: ({ row }) => (
      <span className="text-fg-secondary">
        {formatDateTime(row.original.declaredAt)}
      </span>
    ),
  },
  {
    id: "duration",
    header: "Duration",
    cell: ({ row }) => (
      <span className="font-mono text-sm text-fg-secondary">
        {formatDuration(row.original.declaredAt, row.original.resolvedAt)}
      </span>
    ),
  },
]
