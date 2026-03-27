import { flexRender } from "@tanstack/react-table"

import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import type { DashboardFilters, Pagination } from "@/modules/dashboard/types"
import { useIncidentsTable } from "@/modules/dashboard/hooks/use-incidents-table"
import { incidentsTableColumns } from "@/modules/dashboard/lib/incidents-table-columns"
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
  incidents: IncidentListItem[]
  pagination: Pagination
  filters: DashboardFilters
  severityOptions: SeverityOption[]
}

export function IncidentsTable({ incidents, pagination, filters, severityOptions }: IncidentsTableProps) {
  const {
    table,
    searchInput,
    handleSearchChange,
    selectedSeverities,
    toggleSeverity,
    selectedStatuses,
    toggleStatus,
    setPage,
    setPerPage,
  } = useIncidentsTable(incidents, incidentsTableColumns, filters, pagination)

  return (
    <div className="flex w-full flex-col gap-4">
      <div className="flex items-center justify-between px-4 lg:px-6">
        <h2 className="text-lg font-semibold">Recent Incidents</h2>
      </div>

      <IncidentsTableToolbar
        table={table}
        searchInput={searchInput}
        onSearchChange={handleSearchChange}
        selectedSeverities={selectedSeverities}
        onToggleSeverity={toggleSeverity}
        selectedStatuses={selectedStatuses}
        onToggleStatus={toggleStatus}
        severityOptions={severityOptions}
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

      <IncidentsTablePagination
        pagination={pagination}
        onPageChange={setPage}
        onPerPageChange={setPerPage}
      />
    </div>
  )
}
