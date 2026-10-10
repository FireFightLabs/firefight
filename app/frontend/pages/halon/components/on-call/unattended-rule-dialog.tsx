import { type ChangeEvent, type FormEvent } from "react"
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
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormErrors } from "@/components/form-errors"
import { SearchableSelect } from "@/components/searchable-select"
import { whenClosed } from "@/lib/handlers"
import { UNATTENDED_CAPABILITY_CHOICES, UNATTENDED_MAX_MINUTES, UNATTENDED_METRIC_CHOICES } from "@/lib/generated/constants"
import { unattendedRulePath, unattendedRulesPath } from "@/lib/routes"
import {
  isCapability,
  resourceOptions,
  unattendedRuleFormData,
  unattendedRulePayload,
  type UnattendedRuleFormData,
} from "@/pages/halon/components/on-call/unattended-rule-form"
import type { UnattendedRule, UnattendedRuleResource } from "@/types/serializers"

export function UnattendedRuleDialog({
  open,
  rule,
  resources,
  investigator,
  onDismiss,
}: {
  open: boolean
  rule: UnattendedRule | null
  resources: UnattendedRuleResource[]
  investigator: string
  onDismiss: () => void
}) {
  const form = useForm<UnattendedRuleFormData>(unattendedRuleFormData(rule))
  const { data, setData, errors, clearErrors, processing } = form
  const options = resourceOptions(resources, data.capability, rule)
  const incomplete = data.resourceId === "" || data.threshold === "" || data.minutes === ""

  function patch(changes: Partial<UnattendedRuleFormData>) {
    setData((current) => ({ ...current, ...changes }))
    clearErrors()
  }

  // A resource the new change cannot reach is dropped, so the rule never names one it could not act on.
  function selectCapability(value: string) {
    if (!isCapability(value)) {
      return
    }
    const stillOffered = resourceOptions(resources, value, rule).some((option) => option.value === data.resourceId)
    patch({ capability: value, resourceId: stillOffered ? data.resourceId : "" })
  }

  function selectResource(value: string | null) {
    patch({ resourceId: value ?? "" })
  }

  function selectMetric(value: string) {
    patch({ metric: value })
  }

  function changeThreshold(event: ChangeEvent<HTMLInputElement>) {
    patch({ threshold: event.target.value })
  }

  function changeMinutes(event: ChangeEvent<HTMLInputElement>) {
    patch({ minutes: event.target.value })
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    form.transform(unattendedRulePayload)
    if (rule) {
      form.patch(unattendedRulePath(rule.id), { preserveScroll: true, onSuccess: onDismiss })
    } else {
      form.post(unattendedRulesPath(), { preserveScroll: true, onSuccess: onDismiss })
    }
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{rule ? "Edit unattended rule" : "Add unattended rule"}</DialogTitle>
            <DialogDescription>
              When Halon looks at an alert and proposes exactly this change, it makes it on its own once a fresh reading
              shows the metric above your threshold. It never changes anything else without someone applying it.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="unattended-capability">Halon may</Label>
              <Select value={data.capability} onValueChange={selectCapability}>
                <SelectTrigger id="unattended-capability" className="w-48">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {UNATTENDED_CAPABILITY_CHOICES.map((choice) => (
                    <SelectItem key={choice.value} value={choice.value}>{choice.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="unattended-resource">What on the map</Label>
              <SearchableSelect
                id="unattended-resource"
                value={data.resourceId || null}
                onValueChange={selectResource}
                options={options}
                placeholder="Pick a resource"
                searchPlaceholder="Search the map"
                emptyText="Nothing on the map a connection can do this to"
              />
              {options.length === 0 && (
                <p className="text-muted-foreground text-xs">
                  No connection that holds something on your map offers this yet. Connect the platform that runs it first.
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="unattended-metric">When the average of its</Label>
              <div className="flex flex-wrap items-center gap-2">
                <Select value={data.metric} onValueChange={selectMetric}>
                  <SelectTrigger id="unattended-metric" className="w-44">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {UNATTENDED_METRIC_CHOICES.map((choice) => (
                      <SelectItem key={choice.value} value={choice.value}>{choice.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <span className="text-muted-foreground text-sm">over the last</span>
                <Input
                  id="unattended-minutes"
                  aria-label="Minutes"
                  type="number"
                  min={1}
                  max={UNATTENDED_MAX_MINUTES}
                  value={data.minutes}
                  onChange={changeMinutes}
                  className="w-20"
                />
                <span className="text-muted-foreground text-sm">minutes</span>
              </div>
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="unattended-threshold">Is above</Label>
              <Input
                id="unattended-threshold"
                type="number"
                min={0}
                step="any"
                value={data.threshold}
                onChange={changeThreshold}
                placeholder="50"
                className="w-32"
              />
              <p className="text-muted-foreground text-xs">
                In the units the provider reports, as Halon&apos;s metric charts show them. Halon also needs a grant of the
                change itself. {investigator} holds nothing it was not granted under Gateway, Permissions.
              </p>
            </div>
          </div>

          <FormErrors errors={errors} className="mb-3" />

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onDismiss}>Cancel</Button>
            <Button type="submit" disabled={processing || incomplete}>{rule ? "Save rule" : "Add rule"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
