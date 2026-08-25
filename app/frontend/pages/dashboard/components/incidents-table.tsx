import { router } from "@inertiajs/react"

import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import { incidentPath } from "@/lib/routes"
import type { Pagination } from "@/types"
import type { DashboardFilters } from "@/pages/dashboard/types"
import { useIncidentsTable } from "@/pages/dashboard/hooks/use-incidents-table"
import { incidentsTableColumns } from "@/pages/dashboard/lib/incidents-table-columns"
import { DataTable } from "@/components/data-table"
import { TablePagination } from "@/components/table-pagination"
import { IncidentsTableToolbar } from "@/pages/dashboard/components/incidents-table-toolbar"

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

  function openIncident(incident: IncidentListItem) {
    router.visit(incidentPath(incident.id))
  }

  return (
    <div className="flex w-full flex-col gap-4">
      <div className="flex items-center px-4 lg:px-6">
        <h2 className="text-lg font-semibold">Recent Incidents</h2>
      </div>

      <IncidentsTableToolbar
        searchInput={searchInput}
        onSearchChange={handleSearchChange}
        selectedSeverities={selectedSeverities}
        onToggleSeverity={toggleSeverity}
        selectedStatuses={selectedStatuses}
        onToggleStatus={toggleStatus}
        severityOptions={severityOptions}
      />

      <div className="mx-4 lg:mx-6">
        <DataTable
          table={table}
          onRowClick={openIncident}
          emptyMessage={
            filters.search || filters.severities.length > 0 || filters.statuses.length > 0
              ? "No incidents match your filters."
              : "All clear. No incidents yet."
          }
        />
      </div>

      <TablePagination
        pagination={pagination}
        onPageChange={setPage}
        onPerPageChange={setPerPage}
        totalLabel={`${pagination.totalCount === 1 ? "incident" : "incidents"} total`}
      />
    </div>
  )
}
