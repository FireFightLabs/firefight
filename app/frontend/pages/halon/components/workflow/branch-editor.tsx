import { IconPlus, IconX } from "@tabler/icons-react"
import { type ChangeEvent, useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { WORKFLOW_CONDITION_JOINS } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"
import { ConditionRow } from "@/pages/halon/components/workflow/condition-row"
import {
  type BranchDraft,
  branchConfig,
  branchDraft,
  branchError,
  type ComparisonDraft,
  emptyComparison,
  type RouteDraft,
} from "@/pages/halon/lib/workflow/branch-draft"

interface BranchEditorProps {
  idPrefix: string
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

const JOIN_LABELS = { [WORKFLOW_CONDITION_JOINS.ALL]: "All of these", [WORKFLOW_CONDITION_JOINS.ANY]: "Any of these" }

// A branch's routes, each named and taken when its conditions hold, the first that holds winning, and the route taken
// when none does. A route named here is a way out on the step, which connects to what happens next.
export function BranchEditor({ idPrefix, config, references, disabled, onChange }: BranchEditorProps) {
  const [ draft, setDraft ] = useState<BranchDraft>(() => branchDraft(config))

  function changed(next: BranchDraft) {
    setDraft(next)
    onChange(branchConfig(next), branchError(next))
  }

  function updateRoute(key: string, patch: Partial<RouteDraft>) {
    changed({ ...draft, routes: draft.routes.map((route) => (route.key === key ? { ...route, ...patch } : route)) })
  }

  function renamed(key: string) {
    return (event: ChangeEvent<HTMLInputElement>) => updateRoute(key, { route: event.target.value })
  }

  function joined(key: string) {
    return (value: string) => {
      const join = Object.values(WORKFLOW_CONDITION_JOINS).find((each) => each === value)
      if (join) {
        updateRoute(key, { join })
      }
    }
  }

  function comparisonChanged(route: RouteDraft) {
    return (comparison: ComparisonDraft) => updateRoute(route.key, { comparisons: route.comparisons.map((each) => (each.key === comparison.key ? comparison : each)) })
  }

  function comparisonRemoved(route: RouteDraft, key: string) {
    return () => updateRoute(route.key, { comparisons: route.comparisons.filter((each) => each.key !== key) })
  }

  function addComparison(route: RouteDraft) {
    return () => updateRoute(route.key, { comparisons: [ ...route.comparisons, emptyComparison() ] })
  }

  function removeRoute(key: string) {
    return () => changed({ ...draft, routes: draft.routes.filter((route) => route.key !== key) })
  }

  function addRoute() {
    const route: RouteDraft = { key: crypto.randomUUID(), route: "", join: WORKFLOW_CONDITION_JOINS.ALL, comparisons: [ emptyComparison() ], kept: null }
    changed({ ...draft, routes: [ ...draft.routes, route ] })
  }

  function otherwiseTyped(event: ChangeEvent<HTMLInputElement>) {
    changed({ ...draft, otherwise: event.target.value })
  }

  const error = branchError(draft)

  return (
    <div className="space-y-3">
      {draft.routes.map((route, index) => (
        <div key={route.key} className="space-y-2 rounded-md border border-border-strong p-2.5">
          <div className="flex items-end gap-1.5">
            <div className="flex-1 space-y-1">
              <Label htmlFor={`${idPrefix}-route-${route.key}`} className="text-xs">{index === 0 ? "First route" : "Then route"}</Label>
              <Input id={`${idPrefix}-route-${route.key}`} value={route.route} onChange={renamed(route.key)} placeholder="yes" disabled={disabled} className="font-mono text-xs" />
            </div>
            {!disabled && draft.routes.length > 1 && (
              <button type="button" aria-label={`Remove the route ${route.route}`} className="mb-2 px-1 text-fg-muted hover:text-destructive" onClick={removeRoute(route.key)}>
                <IconX className="size-4" />
              </button>
            )}
          </div>
          {route.kept ? (
            <p className="rounded-md bg-surface-code px-2 py-1.5 font-mono text-xs [overflow-wrap:anywhere] text-fg-secondary">
              {JSON.stringify(route.kept)}
              <span className="mt-1 block font-sans text-fg-muted">Written in a way this form cannot show, so it is kept as it is.</span>
            </p>
          ) : (
            <>
              {route.comparisons.length > 1 && (
                <ToggleGroup type="single" variant="outline" size="sm" value={route.join} onValueChange={joined(route.key)} disabled={disabled} aria-label="Which conditions">
                  {Object.values(WORKFLOW_CONDITION_JOINS).map((join) => <ToggleGroupItem key={join} value={join} className="px-3 text-xs">{JOIN_LABELS[join]}</ToggleGroupItem>)}
                </ToggleGroup>
              )}
              {route.comparisons.map((comparison) => (
                <ConditionRow
                  key={comparison.key}
                  comparison={comparison}
                  references={references}
                  removable={route.comparisons.length > 1}
                  disabled={disabled}
                  onChange={comparisonChanged(route)}
                  onRemove={comparisonRemoved(route, comparison.key)}
                />
              ))}
              {!disabled && (
                <Button type="button" variant="ghost" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addComparison(route)}>
                  <IconPlus className="size-3.5" />
                  Add a condition
                </Button>
              )}
            </>
          )}
        </div>
      ))}
      {!disabled && (
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={addRoute}>
          <IconPlus className="size-3.5" />
          Add a route
        </Button>
      )}
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-otherwise`} className="text-xs">Route when none holds</Label>
        <Input id={`${idPrefix}-otherwise`} value={draft.otherwise} onChange={otherwiseTyped} placeholder="no" disabled={disabled} className="font-mono text-xs" />
        <p className="text-xs text-fg-muted">Leave it empty to go nowhere when no route holds.</p>
      </div>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
