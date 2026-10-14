import { useState, type FormEvent } from "react"
import type { Errors } from "@inertiajs/core"
import { router } from "@inertiajs/react"

import { FormErrors } from "@/components/form-errors"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { WORKFLOW_FREEZE_BEHAVIOURS, WORKFLOW_RUNS_PER_HOUR, type WorkflowFreezeBehaviour } from "@/lib/generated/constants"
import { workflowPath } from "@/lib/routes"
import type { WorkflowDetail } from "@/types/serializers"
import { FREEZE_LABELS } from "@/pages/halon/components/workflows/labels"
import type { TeamChoice } from "@/pages/halon/components/workflows/types"

const NO_TEAM = "none"

interface Draft {
  name: string
  description: string
  ownerTeamId: string
  costCapDollars: string
  runsPerHour: string
  subjectKey: string
  freezeBehaviour: WorkflowFreezeBehaviour
  allClear: boolean
}

function chosenFreeze(value: string): WorkflowFreezeBehaviour {
  return WORKFLOW_FREEZE_BEHAVIOURS.find((behaviour) => behaviour === value) ?? WORKFLOW_FREEZE_BEHAVIOURS[1]
}

function draftFor(workflow: WorkflowDetail): Draft {
  return {
    name: workflow.name,
    description: workflow.description ?? "",
    ownerTeamId: workflow.ownerTeamId ?? NO_TEAM,
    costCapDollars: workflow.costCapCents ? (workflow.costCapCents / 100).toFixed(2) : "",
    runsPerHour: String(workflow.runsPerHour),
    subjectKey: workflow.subjectKey ?? "",
    freezeBehaviour: chosenFreeze(workflow.freezeBehaviour),
    allClear: workflow.allClear,
  }
}

function centsOf(dollars: string): number | null {
  const amount = Number.parseFloat(dollars)
  return Number.isFinite(amount) && amount > 0 ? Math.round(amount * 100) : null
}

// What a workflow is called, who owns it, and what keeps it from running away. Steps and the trigger are changed in the
// draft, not here.
export function SettingsCard({ workflow, teams, canManage }: { workflow: WorkflowDetail; teams: TeamChoice[]; canManage: boolean }) {
  const [draft, setDraft] = useState<Draft>(() => draftFor(workflow))
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)

  function change<Key extends keyof Draft>(key: Key, value: Draft[Key]) {
    setDraft((current) => ({ ...current, [key]: value }))
  }

  function finish() {
    setProcessing(false)
  }

  function cleared() {
    setErrors({})
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    router.patch(workflowPath(workflow.id), {
      name: draft.name,
      description: draft.description,
      owner_team_id: draft.ownerTeamId === NO_TEAM ? "" : draft.ownerTeamId,
      cost_cap_cents: centsOf(draft.costCapDollars) ?? "",
      runs_per_hour: draft.runsPerHour,
      subject_key: draft.subjectKey,
      freeze_behaviour: draft.freezeBehaviour,
      all_clear: draft.allClear,
    }, { preserveScroll: true, onSuccess: cleared, onError: setErrors, onFinish: finish })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Settings</CardTitle>
        <CardDescription className="mt-1">Who owns it, what it may spend, and how it behaves when it meets a limit.</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={submit} className="flex flex-col gap-4">
          <FormErrors errors={errors} />
          <fieldset disabled={!canManage} className="flex flex-col gap-4">
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-name">Name</Label>
                <Input id="workflow-name" value={draft.name} onChange={(event) => change("name", event.target.value)} />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-team">Owning team</Label>
                <Select value={draft.ownerTeamId} onValueChange={(value) => change("ownerTeamId", value)} disabled={!canManage}>
                  <SelectTrigger id="workflow-team" className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NO_TEAM}>No team</SelectItem>
                    {teams.map((team) => <SelectItem key={team.id} value={team.id}>{team.name}</SelectItem>)}
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">A failed run is said in this team&apos;s channel, else to whoever published it.</p>
              </div>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="workflow-description">Description</Label>
              <Textarea id="workflow-description" rows={2} value={draft.description} onChange={(event) => change("description", event.target.value)} />
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-cost-cap">Spending ceiling per run, in dollars</Label>
                <Input id="workflow-cost-cap" type="number" min="0" step="0.01" placeholder="No ceiling" value={draft.costCapDollars}
                  onChange={(event) => change("costCapDollars", event.target.value)} />
                <p className="text-xs text-muted-foreground">AI and sandbox time together. A run that reaches it stops. Empty means none, so only the workspace&apos;s AI budget limits it.</p>
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-runs-per-hour">Most runs per hour</Label>
                <Input id="workflow-runs-per-hour" type="number" min={WORKFLOW_RUNS_PER_HOUR.MIN} max={WORKFLOW_RUNS_PER_HOUR.MAX} value={draft.runsPerHour}
                  placeholder={String(WORKFLOW_RUNS_PER_HOUR.DEFAULT)} onChange={(event) => change("runsPerHour", event.target.value)} />
                <p className="text-xs text-muted-foreground">
                  {WORKFLOW_RUNS_PER_HOUR.MIN} to {WORKFLOW_RUNS_PER_HOUR.MAX}. A run its trigger would start past it is skipped, and this page says how many and when.
                </p>
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-subject">One live run per</Label>
                <Input id="workflow-subject" placeholder="{{inputs.service}}" value={draft.subjectKey} onChange={(event) => change("subjectKey", event.target.value)} />
                <p className="text-xs text-muted-foreground">Empty lets runs overlap. With {"{{inputs.service}}"}, a second run for the same service is refused while the first goes.</p>
              </div>
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div className="flex flex-col gap-2">
                <Label htmlFor="workflow-freeze">When a change lands in a freeze window</Label>
                <Select value={draft.freezeBehaviour} onValueChange={(value) => change("freezeBehaviour", chosenFreeze(value))} disabled={!canManage}>
                  <SelectTrigger id="workflow-freeze" className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {WORKFLOW_FREEZE_BEHAVIOURS.map((behaviour) => <SelectItem key={behaviour} value={behaviour}>{FREEZE_LABELS[behaviour]}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <label className="flex items-center gap-3 self-end pb-2 text-sm">
                <Switch checked={draft.allClear} onCheckedChange={(checked) => change("allClear", checked)} disabled={!canManage} />
                Post a one line all clear when a run finds nothing
              </label>
            </div>
          </fieldset>
          {canManage && (
            <div>
              <Button type="submit" disabled={processing}>Save settings</Button>
            </div>
          )}
        </form>
      </CardContent>
    </Card>
  )
}
