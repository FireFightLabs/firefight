import { useMemo } from "react"
import { IconSearch } from "@tabler/icons-react"

import type { SeverityOption } from "@/types/serializers"
import { STATUS_OPTIONS, STATUS_LABELS } from "@/pages/dashboard/lib/constants"
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
  const severityFilterOptions = useMemo(
    () => severityOptions.map((option) => ({ value: option.slug, label: option.name })),
    [severityOptions],
  )
  const statusFilterOptions = useMemo(
    () => STATUS_OPTIONS.map((status) => ({ value: status, label: STATUS_LABELS[status] })),
    [],
  )

  return (
    <div className="flex flex-wrap items-center gap-2 px-4 lg:px-6">
      <div className="relative w-72">
        <IconSearch className="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search incidents..."
          value={searchInput}
          onChange={(event) => onSearchChange(event.target.value)}
          className="pl-9 h-9 focus-visible:ring-1"
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
