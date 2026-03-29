import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import type { Pagination } from "@/types"
import type { DashboardFilters } from "@/modules/dashboard/types"
import { useIncidentsTable } from "@/modules/dashboard/hooks/use-incidents-table"
import { incidentsTableColumns } from "@/modules/dashboard/lib/incidents-table-columns"
import { DataTable } from "@/components/data-table"
import { TablePagination } from "@/components/table-pagination"
import { IncidentsTableToolbar } from "./incidents-table-toolbar"

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

      <div className="mx-4 lg:mx-6">
        <DataTable table={table} emptyMessage="No incidents found." />
      </div>

      <TablePagination
        pagination={pagination}
        onPageChange={setPage}
        onPerPageChange={setPerPage}
        totalLabel="incident(s) total"
      />
    </div>
  )
}
