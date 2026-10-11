import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { WATCH_NEW_DEPLOY_KEYS } from "@/lib/generated/constants"
import { stepText, type JsonObject } from "@/pages/settings/lib/runbook-procedure"

interface NewDeployFieldsProps {
  id: string
  number: number
  // What the step waits for, or null when it waits for no new deploy.
  newDeploy: JsonObject | null
  // A step reading with a tool names the resource deployed here, since it names none of its own.
  askResource: boolean
  resourceOptions: SearchableSelectOption[]
  onTurn: (on: boolean) => void
  onChange: (key: string, entered: string) => void
}

// A step that waits for a deploy counts only one newer than the deploy live when the watch starts, or the version named.
export function NewDeployFields({ id, number, newDeploy, askResource, resourceOptions, onTurn, onChange }: NewDeployFieldsProps) {
  const on = newDeploy !== null
  const asked = newDeploy ?? {}
  const resource = stepText(asked, WATCH_NEW_DEPLOY_KEYS.RESOURCE)
  const resources = resource && !resourceOptions.some((option) => option.value === resource)
    ? [ { value: resource, label: resource }, ...resourceOptions ]
    : resourceOptions

  function typed(key: string) {
    return (event: ChangeEvent<HTMLInputElement>) => onChange(key, event.target.value)
  }

  function chooseResource(value: string | null) {
    onChange(WATCH_NEW_DEPLOY_KEYS.RESOURCE, value ?? "")
  }

  return (
    <div className="space-y-2">
      <div className="flex items-start gap-2">
        <Switch id={`${id}-new-deploy`} checked={on} onCheckedChange={onTurn} />
        <div className="space-y-0.5">
          <Label htmlFor={`${id}-new-deploy`} className="text-xs font-normal">Wait for a new deploy</Label>
          <p className="text-xs text-muted-foreground">
            Only a deploy newer than the one live when the watch starts counts. Leave these empty for any newer deploy to production.
          </p>
        </div>
      </div>
      {on && (
        <div className="grid gap-2 sm:grid-cols-2">
          {askResource && (
            <div className="sm:col-span-2">
              <SearchableSelect
                value={resource || null}
                onValueChange={chooseResource}
                options={resources}
                placeholder="The resource deployed"
                searchPlaceholder="Search the map"
                emptyText="Nothing on the map by that name"
              />
            </div>
          )}
          <Input aria-label={`Watch ${number} commit`} value={stepText(asked, WATCH_NEW_DEPLOY_KEYS.COMMIT)} onChange={typed(WATCH_NEW_DEPLOY_KEYS.COMMIT)} placeholder="Commit, such as f23b4dc" />
          <Input aria-label={`Watch ${number} tag`} value={stepText(asked, WATCH_NEW_DEPLOY_KEYS.TAG)} onChange={typed(WATCH_NEW_DEPLOY_KEYS.TAG)} placeholder="Tag, such as v1.4.0" />
          <Input aria-label={`Watch ${number} branch`} value={stepText(asked, WATCH_NEW_DEPLOY_KEYS.BRANCH)} onChange={typed(WATCH_NEW_DEPLOY_KEYS.BRANCH)} placeholder="Branch, such as main" />
          <Input aria-label={`Watch ${number} environment`} value={stepText(asked, WATCH_NEW_DEPLOY_KEYS.ENVIRONMENT)} onChange={typed(WATCH_NEW_DEPLOY_KEYS.ENVIRONMENT)} placeholder="Environment, production if empty" />
        </div>
      )}
    </div>
  )
}
