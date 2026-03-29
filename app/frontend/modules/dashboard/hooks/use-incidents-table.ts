import * as React from "react"
import { router } from "@inertiajs/react"
import {
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
  type VisibilityState,
} from "@tanstack/react-table"

import type { IncidentListItem } from "@/types/serializers"
import type { Pagination } from "@/types"
import type { DashboardFilters } from "@/modules/dashboard/types"
import { DEFAULT_PER_PAGE, SEARCH_DEBOUNCE_MS } from "@/modules/dashboard/lib/constants"
import { dashboardPath } from "@/lib/routes"

function navigateDashboard(filters: DashboardFilters, pagination: { page: number; perPage: number }) {
  const params: Record<string, unknown> = {}
  if (filters.search) params.search = filters.search
  if (filters.severities.length > 0) params.severities = filters.severities
  if (filters.statuses.length > 0) params.statuses = filters.statuses
  if (pagination.page > 1) params.page = pagination.page
  if (pagination.perPage !== DEFAULT_PER_PAGE) params.per_page = pagination.perPage

  router.get(dashboardPath(), params, {
    preserveState: true,
    preserveScroll: true,
    only: ["incidents", "pagination", "filters"],
  })
}

export function useIncidentsTable(
  data: IncidentListItem[],
  columns: ColumnDef<IncidentListItem>[],
  filters: DashboardFilters,
  pagination: Pagination,
) {
  const [sorting, setSorting] = React.useState<SortingState>([])
  const [columnVisibility, setColumnVisibility] = React.useState<VisibilityState>({})
  const [searchInput, setSearchInput] = React.useState(filters.search)
  const searchTimerRef = React.useRef<ReturnType<typeof setTimeout>>()
  const filtersRef = React.useRef(filters)
  filtersRef.current = filters
  const paginationRef = React.useRef(pagination)
  paginationRef.current = pagination

  React.useEffect(() => {
    setSearchInput(filters.search)
  }, [filters.search])

  React.useEffect(() => {
    return () => clearTimeout(searchTimerRef.current)
  }, [])

  // eslint-disable-next-line react-hooks/incompatible-library -- TanStack Table is not React Compiler compatible yet
  const table = useReactTable({
    data,
    columns,
    state: { sorting, columnVisibility },
    getRowId: (row) => row.id,
    onSortingChange: setSorting,
    onColumnVisibilityChange: setColumnVisibility,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  const handleSearchChange = React.useCallback((value: string) => {
    setSearchInput(value)
    clearTimeout(searchTimerRef.current)
    searchTimerRef.current = setTimeout(() => {
      navigateDashboard(
        { ...filtersRef.current, search: value },
        { ...paginationRef.current, page: 1 },
      )
    }, SEARCH_DEBOUNCE_MS)
  }, [])

  const toggleSeverity = React.useCallback((slug: string) => {
    const current = [...filtersRef.current.severities]
    const idx = current.indexOf(slug)
    if (idx >= 0) current.splice(idx, 1)
    else current.push(slug)
    navigateDashboard(
      { ...filtersRef.current, severities: current },
      { ...paginationRef.current, page: 1 },
    )
  }, [])

  const toggleStatus = React.useCallback((key: string) => {
    const current = [...filtersRef.current.statuses]
    const idx = current.indexOf(key)
    if (idx >= 0) current.splice(idx, 1)
    else current.push(key)
    navigateDashboard(
      { ...filtersRef.current, statuses: current },
      { ...paginationRef.current, page: 1 },
    )
  }, [])

  const setPage = React.useCallback((page: number) => {
    navigateDashboard(filtersRef.current, { ...paginationRef.current, page })
  }, [])

  const setPerPage = React.useCallback((perPage: number) => {
    navigateDashboard(filtersRef.current, { page: 1, perPage })
  }, [])

  const selectedSeverities = React.useMemo(() => new Set(filters.severities), [filters.severities])
  const selectedStatuses = React.useMemo(() => new Set(filters.statuses), [filters.statuses])

  return {
    table,
    searchInput,
    handleSearchChange,
    selectedSeverities,
    selectedStatuses,
    toggleSeverity,
    toggleStatus,
    setPage,
    setPerPage,
  }
}
