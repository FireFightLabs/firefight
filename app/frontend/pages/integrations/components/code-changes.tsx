import { useState, type ChangeEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import { protectedPathsIntegrationPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"

const PLACEHOLDER = "ci/\ninfra/prod/**\n*.lock"

function linesOf(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

// The paths Halon may not change in a code host connection's repositories, one per line. Save and Cancel show once the
// list changed, and saving says so in a toast. A refusal stays beside what was typed.
export function CodeChanges({
  integrationId,
  paths,
  canManage,
}: {
  integrationId: string
  paths: string[]
  canManage: boolean
}) {
  const saved = paths.join("\n")
  const [text, setText] = useState(saved)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const changed = linesOf(text).join("\n") !== saved

  function edit(event: ChangeEvent<HTMLTextAreaElement>) {
    setText(event.target.value)
    setError(null)
  }

  function refused(errors: Errors) {
    const said = errors.paths
    setError([said].flat().join(" ") || "Firefight could not save the list.")
  }

  function finish() {
    setSaving(false)
  }

  function save() {
    setSaving(true)
    router.patch(
      protectedPathsIntegrationPath(integrationId),
      { paths: linesOf(text) },
      { preserveScroll: true, preserveState: true, onError: refused, onFinish: finish },
    )
  }

  function reset() {
    setText(saved)
    setError(null)
  }

  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-sm font-medium">Code changes</p>
      <div className="border-border flex flex-col gap-2 rounded-lg border px-3 py-2.5">
        <div className="min-w-0">
          <Label htmlFor={`protected-paths-${integrationId}`} className="text-sm font-medium">
            Paths Halon may not change
          </Label>
          <p className="text-muted-foreground text-xs">
            One per line. A folder such as ci/, or a pattern such as infra/prod/** or *.lock. Halon may change any
            other file, and every change arrives for someone to review.
          </p>
        </div>
        <Textarea
          id={`protected-paths-${integrationId}`}
          value={text}
          onChange={edit}
          placeholder={PLACEHOLDER}
          disabled={!canManage || saving}
          aria-invalid={error !== null}
          spellCheck={false}
          className="font-mono text-xs md:text-xs"
        />
        {error && <p className="text-destructive text-xs">{error}</p>}
        {changed && (
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={reset} disabled={saving}>
              Cancel
            </Button>
            <Button size="sm" onClick={save} disabled={saving}>
              Save
            </Button>
          </div>
        )}
      </div>
    </div>
  )
}
