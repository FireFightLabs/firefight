import { router, usePage } from "@inertiajs/react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Label } from "@/components/ui/label"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { OPERATOR_WINDOWS } from "@/pages/operator/generated/constants"
import type { FilterProps, OperatorWindow } from "@/pages/operator/types"

const WINDOW_LABELS: Record<OperatorWindow, string> = {
  [OPERATOR_WINDOWS.DAY]: "Last 24 hours",
  [OPERATOR_WINDOWS.WEEK]: "Last 7 days",
  [OPERATOR_WINDOWS.MONTH]: "Last 30 days",
}
const ALL_WORKSPACES = ""

// The current URL with the window or workspace changed. Drops the page number, since the rows change.
function withFilter(url: string, changes: Record<string, string | null>): string {
  const [path, query] = url.split("?")
  const params = new URLSearchParams(query)
  params.delete("page")
  Object.entries(changes).forEach(([name, value]) => {
    if (value) {
      params.set(name, value)
    } else {
      params.delete(name)
    }
  })
  const next = params.toString()
  return next ? `${path}?${next}` : path
}

function isWindow(value: string): value is OperatorWindow {
  return Object.values<string>(OPERATOR_WINDOWS).includes(value)
}

export function FilterBar({ filter, windows, workspaces }: FilterProps) {
  const { url } = usePage()
  const workspaceOptions: SearchableSelectOption[] = [
    { value: ALL_WORKSPACES, label: `All workspaces (${workspaces.length})` },
    ...workspaces.map((workspace) => ({ value: workspace.id, label: workspace.name })),
  ]

  function pickWorkspace(value: string | null) {
    router.visit(withFilter(url, { workspace: value || null }), { preserveScroll: true })
  }

  // A single toggle group sends an empty value when its pressed item is clicked again, which keeps the window.
  function pickWindow(value: string) {
    if (!isWindow(value)) {
      return
    }
    router.visit(withFilter(url, { window: value }), { preserveScroll: true })
  }

  return (
    <div className="mb-6 flex flex-wrap items-center gap-3">
      <div className="flex items-center gap-2">
        <Label htmlFor="operator-workspace" className="text-muted-foreground text-xs font-normal">
          Workspace
        </Label>
        <div className="w-64">
          <SearchableSelect
            id="operator-workspace"
            value={filter.workspace ?? ALL_WORKSPACES}
            onValueChange={pickWorkspace}
            options={workspaceOptions}
            searchPlaceholder="Search workspaces"
            emptyText="No workspace matches"
          />
        </div>
      </div>
      <ToggleGroup type="single" variant="outline" size="sm" value={filter.window} onValueChange={pickWindow} aria-label="Window">
        {windows.map((choice) => (
          <ToggleGroupItem key={choice} value={choice} className="px-3">
            {WINDOW_LABELS[choice]}
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
    </div>
  )
}
