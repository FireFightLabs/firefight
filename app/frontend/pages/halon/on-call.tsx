import { useState, type ChangeEvent } from "react"
import { Head, router, usePage } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { STORM_CEILING_CENTS } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { halonOnCallPath } from "@/lib/routes"
import { dollars } from "@/pages/halon/components/on-call/unattended-rule-form"
import { UnattendedRulesEditor } from "@/pages/halon/components/on-call/unattended-rules-editor"
import type { OnCallSettings, UnattendedRule, UnattendedRuleResource } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface OnCallPageProps extends SharedProps {
  settings: OnCallSettings
  rules: UnattendedRule[]
  resources: UnattendedRuleResource[]
  investigator: string
}

function ceilingText(cents: number): string {
  return String(cents / 100)
}

function ceilingCents(text: string): number | string {
  const amount = Number(text)
  return text.trim() === "" || Number.isNaN(amount) ? text : Math.round(amount * 100)
}

export default function OnCall() {
  const { settings, rules, resources, investigator } = usePage<OnCallPageProps>().props
  const canManageSettings = useCan("workspace")
  const canManageRules = useCan("permissions")
  const [alertRuns, setAlertRuns] = useState(settings.alertInvestigationsEnabled)
  const [ceiling, setCeiling] = useState(ceilingText(settings.alertStormCeilingCents))
  const [paging, setPaging] = useState(settings.onCallPagingEnabled)
  const [saving, setSaving] = useState(false)
  const [errors, setErrors] = useState<Errors>({})

  function changeCeiling(event: ChangeEvent<HTMLInputElement>) {
    setCeiling(event.target.value)
  }

  function finish() {
    setSaving(false)
  }

  function succeed() {
    setErrors({})
  }

  function save() {
    setSaving(true)
    router.patch(
      halonOnCallPath(),
      {
        alert_investigations_enabled: alertRuns,
        alert_storm_ceiling_cents: ceilingCents(ceiling),
        on_call_paging_enabled: paging,
      },
      { preserveScroll: true, onSuccess: succeed, onError: setErrors, onFinish: finish },
    )
  }

  return (
    <AuthenticatedLayout title="On-call">
      <Head title="On-call" />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <CardTitle>When an alert fires</CardTitle>
            <CardDescription className="mt-1">
              What Halon does when an alert opens an incident at 3am and nobody has looked yet. It reads logs, deploys
              and metrics, ties what broke to its cause, and proposes a fix. Alerts that group into one incident start it
              once.
            </CardDescription>
          </CardHeader>

          <CardContent className="flex flex-col gap-6">
            <div className="flex items-start justify-between gap-6">
              <div className="max-w-prose">
                <Label htmlFor="alert-runs" className="text-foreground">
                  Start Halon when an alert opens an incident
                </Label>
                <p className="mt-1 text-sm text-muted-foreground">
                  Off by default. Halon posts what it finds in the incident&apos;s channel, the same as when someone presses
                  Investigate. A run spends from your AI budget like any other.
                </p>
              </div>
              <Switch id="alert-runs" checked={alertRuns} onCheckedChange={setAlertRuns} disabled={!canManageSettings} />
            </div>

            <div className="max-w-prose">
              <Label htmlFor="storm-ceiling" className="text-foreground">
                Spend at most
              </Label>
              <div className="mt-2 flex items-center gap-2">
                <span className="text-sm text-muted-foreground">$</span>
                <Input
                  id="storm-ceiling"
                  type="number"
                  min={STORM_CEILING_CENTS.MIN / 100}
                  max={STORM_CEILING_CENTS.MAX / 100}
                  step="0.01"
                  value={ceiling}
                  onChange={changeCeiling}
                  className="w-28"
                  disabled={!canManageSettings}
                />
                <span className="text-sm text-muted-foreground">an hour on runs alerts start</span>
              </div>
              {errors.alert_storm_ceiling_cents && (
                <p className="mt-2 text-sm text-destructive">{errors.alert_storm_ceiling_cents}</p>
              )}
              <p className="mt-2 text-sm text-muted-foreground">
                A storm of alerts that do not group together shares this. Each run gets what is left, up to its usual
                budget, and once too little is left the incident says Halon did not start, with a button to start it.
                Runs alerts started in the last hour hold {dollars(settings.stormCommittedCents)} of it now.
              </p>
            </div>

            <div className="flex items-start justify-between gap-6">
              <div className="max-w-prose">
                <Label htmlFor="on-call-paging" className="text-foreground">
                  Page whoever is on call with what Halon found
                </Label>
                <p className="mt-1 text-sm text-muted-foreground">
                  Off by default. Halon finds who is on call with the on-call tool you connected and
                  escalates the incident to them with its answer and the fix it proposes. Approval rules can then let
                  whoever is on call approve a change when nobody working the incident can.
                </p>
              </div>
              <Switch id="on-call-paging" checked={paging} onCheckedChange={setPaging} disabled={!canManageSettings} />
            </div>

            {canManageSettings && (
              <div>
                <Button onClick={save} disabled={saving}>
                  Save
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        <UnattendedRulesEditor rules={rules} resources={resources} investigator={investigator} canManage={canManageRules} />
      </div>
    </AuthenticatedLayout>
  )
}
