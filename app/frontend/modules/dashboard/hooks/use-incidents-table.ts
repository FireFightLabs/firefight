import * as React from "react"
import {
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type ColumnFiltersState,
  type SortingState,
  type VisibilityState,
} from "@tanstack/react-table"

import type { IncidentListItem } from "@/modules/incidents/types"

export function useIncidentsTable(
  data: IncidentListItem[],
  columns: ColumnDef<IncidentListItem>[]
) {
  const [sorting, setSorting] = React.useState<SortingState>([])
  const [columnVisibility, setColumnVisibility] = React.useState<VisibilityState>({})
  const [columnFilters, setColumnFilters] = React.useState<ColumnFiltersState>([])
  const [globalFilter, setGlobalFilter] = React.useState("")
  const [selectedSeverities, setSelectedSeverities] = React.useState<Set<string>>(new Set())
  const [selectedStatuses, setSelectedStatuses] = React.useState<Set<string>>(new Set())
  const [pagination, setPagination] = React.useState({ pageIndex: 0, pageSize: 10 })

  const toggleFilter = (
    setter: React.Dispatch<React.SetStateAction<Set<string>>>,
    value: string
  ) => {
    setter((prev) => {
      const next = new Set(prev)
      if (next.has(value)) next.delete(value)
      else next.add(value)
      return next
    })
  }

  const filteredData = React.useMemo(() => {
    return data.filter((incident) => {
      if (selectedSeverities.size > 0 && !selectedSeverities.has(incident.severity.name))
        return false
      if (selectedStatuses.size > 0 && !selectedStatuses.has(incident.status.lifecycleStage))
        return false
      return true
    })
  }, [data, selectedSeverities, selectedStatuses])

  const table = useReactTable({
    data: filteredData,
    columns,
    state: { sorting, columnVisibility, columnFilters, globalFilter, pagination },
    getRowId: (row) => row.id,
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onColumnVisibilityChange: setColumnVisibility,
    onGlobalFilterChange: setGlobalFilter,
    onPaginationChange: setPagination,
    globalFilterFn: (row, _columnId, filterValue) => {
      const search = filterValue.toLowerCase()
      return (
        row.original.name.toLowerCase().includes(search) ||
        row.original.identifier.toLowerCase().includes(search)
      )
    },
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  return {
    table,
    globalFilter,
    setGlobalFilter,
    selectedSeverities,
    setSelectedSeverities,
    selectedStatuses,
    setSelectedStatuses,
    toggleFilter,
  }
}
