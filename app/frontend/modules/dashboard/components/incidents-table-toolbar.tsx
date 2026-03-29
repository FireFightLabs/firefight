import * as React from "react"
import { IconChevronDown, IconLayoutColumns, IconSearch } from "@tabler/icons-react"
import { type Table } from "@tanstack/react-table"

import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import { STATUS_OPTIONS, STATUS_LABELS } from "@/modules/dashboard/lib/constants"
import { FilterDropdown } from "@/components/filter-dropdown"
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
  const severityFilterOptions = React.useMemo(
    () => severityOptions.map((s) => ({ value: s.slug, label: s.name })),
    [severityOptions],
  )
  const statusFilterOptions = React.useMemo(
    () => STATUS_OPTIONS.map((s) => ({ value: s, label: STATUS_LABELS[s] })),
    [],
  )

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

      <FilterDropdown
        label="Severity"
        options={severityFilterOptions}
        selected={selectedSeverities}
        onToggle={onToggleSeverity}
      />

      <FilterDropdown
        label="Status"
        options={statusFilterOptions}
        selected={selectedStatuses}
        onToggle={onToggleStatus}
      />

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
                  checked={column.getIsVisible()}
                  onCheckedChange={(value) => column.toggleVisibility(!!value)}
                >
                  {typeof column.columnDef.header === "string" ? column.columnDef.header : column.id}
                </DropdownMenuCheckboxItem>
              ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}
