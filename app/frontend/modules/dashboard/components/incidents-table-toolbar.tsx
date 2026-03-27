import { IconChevronDown, IconLayoutColumns, IconSearch } from "@tabler/icons-react"
import { type Table } from "@tanstack/react-table"

import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import { STATUS_OPTIONS, STATUS_LABELS } from "@/modules/dashboard/lib/constants"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"

interface IncidentsTableToolbarProps {
  table: Table<IncidentListItem>
  searchInput: string
  onSearchChange: (value: string) => void
  selectedSeverities: Set<string>
  onToggleSeverity: (slug: string) => void
  selectedStatuses: Set<string>
  onToggleStatus: (key: string) => void
  severityOptions: SeverityOption[]
}

export function IncidentsTableToolbar({
  table,
  searchInput,
  onSearchChange,
  selectedSeverities,
  onToggleSeverity,
  selectedStatuses,
  onToggleStatus,
  severityOptions,
}: IncidentsTableToolbarProps) {
  return (
    <div className="flex flex-wrap items-center gap-2 px-4 lg:px-6">
      <div className="relative flex-1 min-w-[200px] max-w-sm">
        <IconSearch className="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search incidents..."
          value={searchInput}
          onChange={(e) => onSearchChange(e.target.value)}
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
          {severityOptions.map((severity) => (
            <DropdownMenuCheckboxItem
              key={severity.slug}
              checked={selectedSeverities.has(severity.slug)}
              onCheckedChange={() => onToggleSeverity(severity.slug)}
              onSelect={(e) => e.preventDefault()}
            >
              {severity.name}
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
          {STATUS_OPTIONS.map((status) => (
            <DropdownMenuCheckboxItem
              key={status}
              checked={selectedStatuses.has(status)}
              onCheckedChange={() => onToggleStatus(status)}
              onSelect={(e) => e.preventDefault()}
            >
              {STATUS_LABELS[status]}
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
                  typeof column.accessorFn !== "undefined" && column.getCanHide()
              )
              .map((column) => (
                <DropdownMenuCheckboxItem
                  key={column.id}
                  className="capitalize"
                  checked={column.getIsVisible()}
                  onCheckedChange={(value) => column.toggleVisibility(!!value)}
                >
                  {column.id}
                </DropdownMenuCheckboxItem>
              ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}
