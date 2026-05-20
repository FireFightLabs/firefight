import { useCallback, useEffect, useMemo, useRef, useState } from "react"
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
  const [sorting, setSorting] = useState<SortingState>([])
  const [columnVisibility, setColumnVisibility] = useState<VisibilityState>({})
  const [searchInput, setSearchInput] = useState(filters.search ?? "")
  const searchTimerRef = useRef<ReturnType<typeof setTimeout>>()
  const searchInputRef = useRef(filters.search ?? "")
  const filtersRef = useRef(filters)
  filtersRef.current = filters
  const paginationRef = useRef(pagination)
  paginationRef.current = pagination

  useEffect(() => {
    setSearchInput(filters.search ?? "")
    searchInputRef.current = filters.search ?? ""
  }, [filters.search])

  useEffect(() => {
    return () => clearTimeout(searchTimerRef.current)
  }, [])

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

  const handleSearchChange = useCallback((value: string) => {
    setSearchInput(value)
    searchInputRef.current = value
    clearTimeout(searchTimerRef.current)
    searchTimerRef.current = setTimeout(() => {
      navigateDashboard(
        { ...filtersRef.current, search: value },
        { ...paginationRef.current, page: 1 },
      )
    }, SEARCH_DEBOUNCE_MS)
  }, [])

  const toggleSeverity = useCallback((slug: string) => {
    const current = [...filtersRef.current.severities]
    const idx = current.indexOf(slug)
    if (idx >= 0) current.splice(idx, 1)
    else current.push(slug)
    clearTimeout(searchTimerRef.current)
    navigateDashboard(
      { ...filtersRef.current, severities: current, search: searchInputRef.current },
      { ...paginationRef.current, page: 1 },
    )
  }, [])

  const toggleStatus = useCallback((key: string) => {
    const current = [...filtersRef.current.statuses]
    const idx = current.indexOf(key)
    if (idx >= 0) current.splice(idx, 1)
    else current.push(key)
    clearTimeout(searchTimerRef.current)
    navigateDashboard(
      { ...filtersRef.current, statuses: current, search: searchInputRef.current },
      { ...paginationRef.current, page: 1 },
    )
  }, [])

  const setPage = useCallback((page: number) => {
    navigateDashboard(filtersRef.current, { ...paginationRef.current, page })
  }, [])

  const setPerPage = useCallback((perPage: number) => {
    navigateDashboard(filtersRef.current, { page: 1, perPage })
  }, [])

  const selectedSeverities = useMemo(() => new Set(filters.severities), [filters.severities])
  const selectedStatuses = useMemo(() => new Set(filters.statuses), [filters.statuses])

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
