import { type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormErrors } from "@/components/form-errors"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { whenClosed } from "@/lib/handlers"
import { allowancePath, allowancesPath } from "@/lib/routes"
import type { Allowance, AllowanceChoice, EnvironmentOption } from "@/types/serializers"

// What the entry names is one choice, a capability or one connection's tool, told apart by a prefix the server never sees.
const CAPABILITY = "capability:"
const TOOL = "tool:"
// Any connection and every environment are choices of their own, sent as an empty value the server saves as none.
const ANYWHERE = "anywhere"

interface AllowanceFormData {
  change: string
  integration: string
  environment: string
}

function formData(allowance: Allowance | null): AllowanceFormData {
  const change = allowance?.capability ? `${CAPABILITY}${allowance.capability}` : allowance?.actionKey ? `${TOOL}${allowance.actionKey}` : ""
  return { change, integration: allowance?.integration ?? ANYWHERE, environment: allowance?.environmentId ?? ANYWHERE }
}

function payload(data: AllowanceFormData) {
  const capability = data.change.startsWith(CAPABILITY) ? data.change.slice(CAPABILITY.length) : ""
  const actionKey = data.change.startsWith(TOOL) ? data.change.slice(TOOL.length) : ""
  return {
    allowance: {
      capability,
      action_key: actionKey,
      integration: capability && data.integration !== ANYWHERE ? data.integration : "",
      environment: data.environment === ANYWHERE ? "" : data.environment,
    },
  }
}

export function AllowanceDialog({
  open,
  allowance,
  capabilities,
  tools,
  environments,
  onDismiss,
}: {
  open: boolean
  allowance: Allowance | null
  capabilities: AllowanceChoice[]
  tools: AllowanceChoice[]
  environments: EnvironmentOption[]
  onDismiss: () => void
}) {
  const form = useForm<AllowanceFormData>(formData(allowance))
  const { data, setData, errors, clearErrors, processing } = form
  const capability = capabilities.find((choice) => `${CAPABILITY}${choice.value}` === data.change) ?? null
  const options: SearchableSelectOption[] = [
    ...capabilities.map((choice) => ({ value: `${CAPABILITY}${choice.value}`, label: choice.label, group: "Anything on the resource map" })),
    ...tools.map((choice) => ({ value: `${TOOL}${choice.value}`, label: choice.label, group: "One connection's tool" })),
  ]

  function patch(changes: Partial<AllowanceFormData>) {
    setData((current) => ({ ...current, ...changes }))
    clearErrors()
  }

  // A connection belongs to a capability, so choosing a tool, which already names its connection, drops it.
  function selectChange(value: string | null) {
    patch({ change: value ?? "", integration: ANYWHERE })
  }

  function selectIntegration(value: string) {
    patch({ integration: value })
  }

  function selectEnvironment(value: string) {
    patch({ environment: value })
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform(payload)
    if (allowance) {
      form.patch(allowancePath(allowance.id), { preserveScroll: true, onSuccess: onDismiss })
    } else {
      form.post(allowancesPath(), { preserveScroll: true, onSuccess: onDismiss })
    }
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{allowance ? "Edit what Halon may do" : "Let Halon do this without asking"}</DialogTitle>
            <DialogDescription>
              In anyone&apos;s chat, Halon makes this change without asking first, then says what it did in the chat. It
              still needs the person&apos;s permission for it, and an approval rule still asks its approvers.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="allowance-change">Halon may</Label>
              <SearchableSelect
                id="allowance-change"
                value={data.change || null}
                onValueChange={selectChange}
                options={options}
                placeholder="Pick a change"
                searchPlaceholder="Search changes"
                emptyText="No change Halon can make here can be on this list"
              />
              <p className="text-muted-foreground text-xs">
                Changes to who can reach something or to a secret always ask a person, so they are never offered. Nor is a
                tool that reaches a whole API, one that writes rows to a database, or one on a server Firefight cannot see
                inside.
              </p>
            </div>

            {capability && (
              <div className="flex flex-col gap-2">
                <Label htmlFor="allowance-integration">On</Label>
                <Select value={data.integration} onValueChange={selectIntegration}>
                  <SelectTrigger id="allowance-integration" className="w-72">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={ANYWHERE}>Any connection</SelectItem>
                    {capability.connections.map((connection) => (
                      <SelectItem key={connection.value} value={connection.value}>{connection.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            <div className="flex flex-col gap-2">
              <Label htmlFor="allowance-environment">In</Label>
              <Select value={data.environment} onValueChange={selectEnvironment}>
                <SelectTrigger id="allowance-environment" className="w-72">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ANYWHERE}>Every environment</SelectItem>
                  {environments.map((environment) => (
                    <SelectItem key={environment.id} value={environment.id}>{environment.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <FormErrors errors={errors} className="mb-3" />

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onDismiss}>Cancel</Button>
            <Button type="submit" disabled={processing || data.change === ""}>{allowance ? "Save" : "Add"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
