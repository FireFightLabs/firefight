import { router, usePage } from "@inertiajs/react"

import { OPERATOR_WINDOWS } from "@/lib/generated/constants"
import type { FilterProps, OperatorWindow } from "@/pages/operator/types"

const WINDOW_LABELS: Record<OperatorWindow, string> = {
  [OPERATOR_WINDOWS.DAY]: "Last 24 hours",
  [OPERATOR_WINDOWS.WEEK]: "Last 7 days",
  [OPERATOR_WINDOWS.MONTH]: "Last 30 days",
}
const ALL_WORKSPACES = ""

// The same address with the window or workspace changed, back on the first page since the rows are different ones.
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

export function FilterBar({ filter, windows, workspaces }: FilterProps) {
  const { url } = usePage()

  function pickWorkspace(event: React.ChangeEvent<HTMLSelectElement>) {
    router.visit(withFilter(url, { workspace: event.target.value || null }), { preserveScroll: true })
  }

  function pickWindow(choice: OperatorWindow) {
    router.visit(withFilter(url, { window: choice }), { preserveScroll: true })
  }

  return (
    <div className="mb-6 flex flex-wrap items-center gap-3">
      <label className="text-muted-foreground flex items-center gap-2 text-xs">
        Workspace
        <select
          id="operator-workspace"
          value={filter.workspace ?? ALL_WORKSPACES}
          onChange={pickWorkspace}
          className="bg-card h-8 max-w-64 rounded-md border border-border px-2 text-xs text-foreground"
        >
          <option value={ALL_WORKSPACES}>All workspaces ({workspaces.length})</option>
          {workspaces.map((workspace) => (
            <option key={workspace.id} value={workspace.id}>{workspace.name}</option>
          ))}
        </select>
      </label>
      <div role="group" aria-label="Window" className="flex items-center gap-1 rounded-lg border border-border bg-card p-0.5">
        {windows.map((choice) => (
          <button
            key={choice}
            type="button"
            aria-pressed={filter.window === choice}
            onClick={() => pickWindow(choice)}
            className={`h-7 rounded-md px-2.5 text-xs transition-colors ${filter.window === choice ? "bg-primary/10 text-primary" : "text-muted-foreground hover:text-foreground"}`}
          >
            {WINDOW_LABELS[choice]}
          </button>
        ))}
      </div>
    </div>
  )
}
