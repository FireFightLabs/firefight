import {
  IconChevronDown,
  IconChevronLeft,
  IconChevronRight,
  IconChevronsLeft,
  IconChevronsRight,
  IconCircleCheckFilled,
  IconCircleDashedCheck,
  IconLayoutColumns,
  IconLoader,
  IconSearch,
  IconUrgent,
} from "@tabler/icons-react"
import {
  flexRender,
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

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import * as React from "react"

interface Incident {
  id: string
  identifier: string
  name: string
  severity: { name: string; rank: number }
  status: { name: string; lifecycleStage: string }
  lead: string | null
  declaredAt: string
  resolvedAt: string | null
}

const severityVariant = (rank: number) => {
  if (rank >= 4) return "destructive" as const
  if (rank >= 3) return "default" as const
  return "secondary" as const
}

const statusVariant = (lifecycleStage: string) => {
  switch (lifecycleStage) {
    case "active":
      return "default" as const
    case "closed":
      return "secondary" as const
    default:
      return "outline" as const
  }
}

function formatDuration(declaredAt: string, resolvedAt: string | null): string {
  const start = new Date(declaredAt)
  const end = resolvedAt ? new Date(resolvedAt) : new Date()
  const diffMs = end.getTime() - start.getTime()
  const minutes = Math.floor(diffMs / 60000)

  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  const remainingMinutes = minutes % 60
  if (hours < 24) return `${hours}h ${remainingMinutes}m`
  const days = Math.floor(hours / 24)
  return `${days}d ${hours % 24}h`
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}

const columns: ColumnDef<Incident>[] = [
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
      <span className="font-medium">{row.original.name}</span>
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

const mockIncidents: Incident[] = [
  {
    id: "1",
    identifier: "INC-042",
    name: "Payment processing failures in EU region",
    severity: { name: "Critical", rank: 4 },
    status: { name: "Investigating", lifecycleStage: "active" },
    lead: "Sarah Chen",
    declaredAt: "2026-03-25T08:15:00Z",
    resolvedAt: null,
  },
  {
    id: "2",
    identifier: "INC-041",
    name: "Elevated API latency on /v2/orders endpoint",
    severity: { name: "High", rank: 3 },
    status: { name: "Monitoring", lifecycleStage: "active" },
    lead: "James Wilson",
    declaredAt: "2026-03-25T06:30:00Z",
    resolvedAt: null,
  },
  {
    id: "3",
    identifier: "INC-040",
    name: "CDN cache invalidation delays",
    severity: { name: "Medium", rank: 2 },
    status: { name: "Investigating", lifecycleStage: "active" },
    lead: null,
    declaredAt: "2026-03-24T22:00:00Z",
    resolvedAt: null,
  },
  {
    id: "4",
    identifier: "INC-039",
    name: "Database connection pool exhaustion",
    severity: { name: "Critical", rank: 4 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "Maria Garcia",
    declaredAt: "2026-03-24T14:20:00Z",
    resolvedAt: "2026-03-24T15:45:00Z",
  },
  {
    id: "5",
    identifier: "INC-038",
    name: "SSO login failures for SAML customers",
    severity: { name: "High", rank: 3 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "Alex Kim",
    declaredAt: "2026-03-24T09:10:00Z",
    resolvedAt: "2026-03-24T10:30:00Z",
  },
  {
    id: "6",
    identifier: "INC-037",
    name: "Email notification delivery delays",
    severity: { name: "Low", rank: 1 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "Jordan Park",
    declaredAt: "2026-03-23T16:45:00Z",
    resolvedAt: "2026-03-23T17:20:00Z",
  },
  {
    id: "7",
    identifier: "INC-036",
    name: "Mobile app crash on iOS 19.2",
    severity: { name: "High", rank: 3 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "Sarah Chen",
    declaredAt: "2026-03-23T11:00:00Z",
    resolvedAt: "2026-03-23T13:15:00Z",
  },
  {
    id: "8",
    identifier: "INC-035",
    name: "Webhook delivery failures to partner endpoints",
    severity: { name: "Medium", rank: 2 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "James Wilson",
    declaredAt: "2026-03-22T19:30:00Z",
    resolvedAt: "2026-03-22T20:45:00Z",
  },
  {
    id: "9",
    identifier: "INC-034",
    name: "Search index replication lag across clusters",
    severity: { name: "Medium", rank: 2 },
    status: { name: "Triage", lifecycleStage: "active" },
    lead: null,
    declaredAt: "2026-03-25T09:45:00Z",
    resolvedAt: null,
  },
  {
    id: "10",
    identifier: "INC-033",
    name: "Scheduled reports generating with stale data",
    severity: { name: "Low", rank: 1 },
    status: { name: "Resolved", lifecycleStage: "closed" },
    lead: "Maria Garcia",
    declaredAt: "2026-03-21T14:00:00Z",
    resolvedAt: "2026-03-21T15:30:00Z",
  },
]

const severities = ["Critical", "High", "Medium", "Low"] as const
const statuses = ["active", "closed"] as const
const statusLabels: Record<string, string> = {
  active: "Active",
  closed: "Closed",
}

export function DataTable() {
  const [sorting, setSorting] = React.useState<SortingState>([])
  const [columnVisibility, setColumnVisibility] =
    React.useState<VisibilityState>({})
  const [columnFilters, setColumnFilters] =
    React.useState<ColumnFiltersState>([])
  const [globalFilter, setGlobalFilter] = React.useState("")
  const [selectedSeverities, setSelectedSeverities] = React.useState<Set<string>>(new Set())
  const [selectedStatuses, setSelectedStatuses] = React.useState<Set<string>>(new Set())
  const [pagination, setPagination] = React.useState({
    pageIndex: 0,
    pageSize: 10,
  })

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
    return mockIncidents.filter((incident) => {
      if (selectedSeverities.size > 0 && !selectedSeverities.has(incident.severity.name))
        return false
      if (selectedStatuses.size > 0 && !selectedStatuses.has(incident.status.lifecycleStage))
        return false
      return true
    })
  }, [selectedSeverities, selectedStatuses])

  const table = useReactTable({
    data: filteredData,
    columns,
    state: {
      sorting,
      columnVisibility,
      columnFilters,
      globalFilter,
      pagination,
    },
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

  return (
    <div className="flex w-full flex-col gap-4">
      <div className="flex items-center justify-between px-4 lg:px-6">
        <h2 className="text-lg font-semibold">Recent Incidents</h2>
      </div>
      <div className="flex flex-wrap items-center gap-2 px-4 lg:px-6">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <IconSearch className="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search incidents..."
            value={globalFilter}
            onChange={(e) => setGlobalFilter(e.target.value)}
            className="pl-9 h-9"
          />
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" className="h-9">
              Severity
              {selectedSeverities.size > 0 && (
                <Badge variant="secondary" className="ml-1 rounded-sm px-1">
                  {selectedSeverities.size}
                </Badge>
              )}
              <IconChevronDown />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-40">
            {severities.map((severity) => (
              <DropdownMenuCheckboxItem
                key={severity}
                checked={selectedSeverities.has(severity)}
                onCheckedChange={() => toggleFilter(setSelectedSeverities, severity)}
                onSelect={(e) => e.preventDefault()}
              >
                {severity}
              </DropdownMenuCheckboxItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" className="h-9">
              Status
              {selectedStatuses.size > 0 && (
                <Badge variant="secondary" className="ml-1 rounded-sm px-1">
                  {selectedStatuses.size}
                </Badge>
              )}
              <IconChevronDown />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-40">
            {statuses.map((status) => (
              <DropdownMenuCheckboxItem
                key={status}
                checked={selectedStatuses.has(status)}
                onCheckedChange={() => toggleFilter(setSelectedStatuses, status)}
                onSelect={(e) => e.preventDefault()}
              >
                {statusLabels[status]}
              </DropdownMenuCheckboxItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <div className="ml-auto flex items-center gap-2">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                <IconLayoutColumns />
                <span className="hidden lg:inline">Customize Columns</span>
                <span className="lg:hidden">Columns</span>
                <IconChevronDown />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              {table
                .getAllColumns()
                .filter(
                  (column) =>
                    typeof column.accessorFn !== "undefined" &&
                    column.getCanHide()
                )
                .map((column) => (
                  <DropdownMenuCheckboxItem
                    key={column.id}
                    className="capitalize"
                    checked={column.getIsVisible()}
                    onCheckedChange={(value) =>
                      column.toggleVisibility(!!value)
                    }
                  >
                    {column.id}
                  </DropdownMenuCheckboxItem>
                ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
      <div className="overflow-hidden rounded-lg border mx-4 lg:mx-6">
        <Table>
          <TableHeader className="sticky top-0 z-10 bg-muted">
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id} colSpan={header.colSpan}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
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
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext()
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center"
                >
                  No incidents found.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
      <div className="flex items-center justify-between px-4 lg:px-6">
        <div className="hidden flex-1 text-sm text-muted-foreground lg:flex">
          {table.getFilteredRowModel().rows.length} incident(s) total
        </div>
        <div className="flex w-full items-center gap-8 lg:w-fit">
          <div className="hidden items-center gap-2 lg:flex">
            <Label htmlFor="rows-per-page" className="text-sm font-medium">
              Rows per page
            </Label>
            <Select
              value={`${table.getState().pagination.pageSize}`}
              onValueChange={(value) => {
                table.setPageSize(Number(value))
              }}
            >
              <SelectTrigger size="sm" className="w-20" id="rows-per-page">
                <SelectValue
                  placeholder={table.getState().pagination.pageSize}
                />
              </SelectTrigger>
              <SelectContent side="top">
                {[10, 20, 30, 40, 50].map((pageSize) => (
                  <SelectItem key={pageSize} value={`${pageSize}`}>
                    {pageSize}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex w-fit items-center justify-center text-sm font-medium">
            Page {table.getState().pagination.pageIndex + 1} of{" "}
            {table.getPageCount()}
          </div>
          <div className="ml-auto flex items-center gap-2 lg:ml-0">
            <Button
              variant="outline"
              className="hidden h-8 w-8 p-0 lg:flex"
              onClick={() => table.setPageIndex(0)}
              disabled={!table.getCanPreviousPage()}
            >
              <span className="sr-only">Go to first page</span>
              <IconChevronsLeft />
            </Button>
            <Button
              variant="outline"
              className="size-8"
              size="icon"
              onClick={() => table.previousPage()}
              disabled={!table.getCanPreviousPage()}
            >
              <span className="sr-only">Go to previous page</span>
              <IconChevronLeft />
            </Button>
            <Button
              variant="outline"
              className="size-8"
              size="icon"
              onClick={() => table.nextPage()}
              disabled={!table.getCanNextPage()}
            >
              <span className="sr-only">Go to next page</span>
              <IconChevronRight />
            </Button>
            <Button
              variant="outline"
              className="hidden size-8 lg:flex"
              size="icon"
              onClick={() => table.setPageIndex(table.getPageCount() - 1)}
              disabled={!table.getCanNextPage()}
            >
              <span className="sr-only">Go to last page</span>
              <IconChevronsRight />
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
