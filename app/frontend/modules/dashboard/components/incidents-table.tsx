import { flexRender } from "@tanstack/react-table"

import type { IncidentListItem } from "@/modules/incidents/types"
import { useIncidentsTable } from "@/modules/dashboard/hooks/use-incidents-table"
import { incidentsTableColumns } from "@/modules/dashboard/lib/incidents-table-columns"
import { mockIncidents } from "@/modules/dashboard/lib/mock-data"
import { IncidentsTableToolbar } from "./incidents-table-toolbar"
import { IncidentsTablePagination } from "./incidents-table-pagination"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

interface IncidentsTableProps {
  incidents?: IncidentListItem[]
}

export function IncidentsTable({ incidents = mockIncidents }: IncidentsTableProps) {
  const {
    table,
    globalFilter,
    setGlobalFilter,
    selectedSeverities,
    setSelectedSeverities,
    selectedStatuses,
    setSelectedStatuses,
    toggleFilter,
  } = useIncidentsTable(incidents, incidentsTableColumns)

  return (
    <div className="flex w-full flex-col gap-4">
      <div className="flex items-center justify-between px-4 lg:px-6">
        <h2 className="text-lg font-semibold">Recent Incidents</h2>
      </div>

      <IncidentsTableToolbar
        table={table}
        globalFilter={globalFilter}
        onGlobalFilterChange={setGlobalFilter}
        selectedSeverities={selectedSeverities}
        onToggleSeverity={(v) => toggleFilter(setSelectedSeverities, v)}
        selectedStatuses={selectedStatuses}
        onToggleStatus={(v) => toggleFilter(setSelectedStatuses, v)}
      />

      <div className="overflow-hidden rounded-lg border mx-4 lg:mx-6">
        <Table>
          <TableHeader className="sticky top-0 z-10 bg-muted">
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id} colSpan={header.colSpan}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(header.column.columnDef.header, header.getContext())}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows?.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow key={row.id}>
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={incidentsTableColumns.length}
                  className="h-24 text-center"
                >
                  No incidents found.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <IncidentsTablePagination table={table} />
    </div>
  )
}
