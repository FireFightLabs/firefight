import * as React from "react"
import { IconSearch } from "@tabler/icons-react"

import type { SeverityOption } from "@/types/serializers"
import { STATUS_OPTIONS, STATUS_LABELS } from "@/modules/dashboard/lib/constants"
import { FilterDropdown } from "@/components/filter-dropdown"
import { Input } from "@/components/ui/input"

interface IncidentsTableToolbarProps {
  searchInput: string
  onSearchChange: (value: string) => void
  selectedSeverities: Set<string>
  onToggleSeverity: (slug: string) => void
  selectedStatuses: Set<string>
  onToggleStatus: (key: string) => void
  severityOptions: SeverityOption[]
}

export function IncidentsTableToolbar({
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
    </div>
  )
}
