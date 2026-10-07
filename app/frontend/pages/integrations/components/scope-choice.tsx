import { useState } from "react"
import { router } from "@inertiajs/react"

import type { Integration } from "@/types/serializers"
import { scopeOptionsIntegrationPath, scopesIntegrationPath } from "@/lib/routes"
import { requestJson } from "@/lib/http"
import { Button } from "@/components/ui/button"
import { ScopeSelect, type ScopeListing } from "@/components/integrations/scope-select"

type Scopes = NonNullable<Integration["environments"][number]["scopes"]>

function same(left: string[], right: string[]) {
  return left.length === right.length && left.every((value) => right.includes(value))
}

// What one environment of a connection reads at its provider, such as which Northflank projects, chosen again from what
// its stored credentials can read now. Saving reads the connection again at once and says so in a toast.
export function ScopeChoice({
  integrationId,
  rowId,
  scopes,
  canManage,
}: {
  integrationId: string
  rowId: string
  scopes: Scopes
  canManage: boolean
}) {
  const [values, setValues] = useState(scopes.values)
  const [saving, setSaving] = useState(false)
  const changed = !same(values, scopes.values)

  async function listScopes(): Promise<ScopeListing> {
    const answer = await requestJson<ScopeListing>(
      scopeOptionsIntegrationPath(integrationId, { environment_row_id: rowId }),
      { method: "GET" },
    )
    return answer.data ?? { options: [], error: "Firefight could not list them." }
  }

  function finish() {
    setSaving(false)
  }

  function save() {
    setSaving(true)
    router.patch(
      scopesIntegrationPath(integrationId),
      { environment_row_id: rowId, values },
      { preserveScroll: true, onFinish: finish },
    )
  }

  function reset() {
    setValues(scopes.values)
  }

  return (
    <div className="flex flex-col gap-1.5 px-3 pb-2.5">
      <div className="min-w-0">
        <p className="text-sm font-medium">{scopes.label}</p>
        <p className="text-muted-foreground text-xs">{scopes.hint}</p>
      </div>
      <ScopeSelect
        label={scopes.label}
        placeholder={`Choose ${scopes.label.toLowerCase()}`}
        value={values}
        known={scopes.options}
        listingKey={rowId}
        load={listScopes}
        onChange={setValues}
        disabled={!canManage || saving}
      />
      {changed && (
        <div className="flex justify-end gap-2">
          <Button size="sm" variant="ghost" onClick={reset} disabled={saving}>
            Cancel
          </Button>
          <Button size="sm" onClick={save} disabled={saving || values.length === 0}>
            Save
          </Button>
        </div>
      )}
    </div>
  )
}
