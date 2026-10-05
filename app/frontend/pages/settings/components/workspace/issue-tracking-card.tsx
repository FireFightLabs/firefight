import { useState } from "react"
import { Link } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"
import { IconCheck, IconCopy } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { integrationsPath } from "@/lib/routes"
import type { WorkspaceSettings } from "@/types/serializers"

// No tracker is no connection, and a connection's slug never holds a hyphen, so this never names one.
const NO_TRACKER = "no-tracker"

export function trackerChoice(slug: string | null | undefined): string {
  return slug ?? NO_TRACKER
}

export function trackerSlug(choice: string): string {
  return choice === NO_TRACKER ? "" : choice
}

export interface IssueTrackingState {
  tracker: string
  creation: WorkspaceSettings["issueCreation"]
  target: Record<string, string>
  secret: string
}

export function IssueTrackingCard({
  settings,
  webhookUrl,
  state,
  errors,
  onChange,
}: {
  settings: WorkspaceSettings
  webhookUrl: string | null
  state: IssueTrackingState
  errors: Errors
  onChange: (next: IssueTrackingState) => void
}) {
  const [copied, setCopied] = useState(false)
  const chosen = settings.issueTrackers.find((choice) => trackerChoice(choice.value) === state.tracker)
  const savedTracker = trackerChoice(settings.issueTracker) === state.tracker
  const connected = settings.issueTrackers.length > 1
  const hasTracker = state.tracker !== NO_TRACKER

  function chooseTracker(value: string) {
    const target = trackerChoice(settings.issueTracker) === value ? settings.issueTrackerTarget : {}
    onChange({ ...state, tracker: value, target })
  }

  function chooseCreation(value: string) {
    const creation = settings.issueCreations.find((choice) => choice.value === value)?.value
    if (creation) {
      onChange({ ...state, creation })
    }
  }

  function changeTarget(key: string, value: string) {
    onChange({ ...state, target: { ...state.target, [key]: value } })
  }

  function changeSecret(event: React.ChangeEvent<HTMLInputElement>) {
    onChange({ ...state, secret: event.target.value })
  }

  function markCopied() {
    setCopied(true)
  }

  function copyAddress() {
    if (webhookUrl) {
      void navigator.clipboard.writeText(webhookUrl).then(markCopied)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Issue tracking</CardTitle>
        <CardDescription className="mt-1">
          Keep an incident&apos;s actions and follow-ups in step with issues in a tracker you connected. A change to an
          item&apos;s title, status or assignee reaches its issue, and a change made to the issue comes back. Closing either
          one closes the other, and reopening either one reopens the other. Choosing a tracker switches on the tools this
          uses and grants exactly those to Firefight issue sync, which makes every change in the tracker, so it works
          whoever made the item. Your approval rules still apply.
        </CardDescription>
      </CardHeader>

      <CardContent className="flex flex-col gap-6">
        <div className="max-w-prose">
          <Label htmlFor="issue-tracker" className="text-foreground">
            Issue tracker
          </Label>
          <div className="mt-2">
            <Select value={state.tracker} onValueChange={chooseTracker}>
              <SelectTrigger id="issue-tracker" className="w-72">
                <SelectValue placeholder="Choose an issue tracker" />
              </SelectTrigger>
              <SelectContent>
                {settings.issueTrackers.map((choice) => (
                  <SelectItem key={trackerChoice(choice.value)} value={trackerChoice(choice.value)}>
                    {choice.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {errors.issue_tracker && <p className="mt-2 text-sm text-destructive">{errors.issue_tracker}</p>}
          {savedTracker && settings.issueCreationBlockedReason && (
            <p className="mt-2 text-sm text-destructive">{settings.issueCreationBlockedReason}</p>
          )}
          {!connected && (
            <p className="mt-2 text-sm text-muted-foreground">
              No issue tracker is connected yet. Connect one under{" "}
              <Link href={integrationsPath()} className="underline underline-offset-4">
                Integrations
              </Link>{" "}
              to choose it here.
            </p>
          )}
        </div>

        <div className="max-w-prose">
          <Label htmlFor="issue-creation" className="text-foreground">
            Open an issue for a new item
          </Label>
          <div className="mt-2">
            <Select value={state.creation} onValueChange={chooseCreation}>
              <SelectTrigger id="issue-creation" className="w-72">
                <SelectValue placeholder="Choose when" />
              </SelectTrigger>
              <SelectContent>
                {settings.issueCreations.map((choice) => (
                  <SelectItem key={choice.value} value={choice.value}>
                    {choice.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {errors.issue_creation && <p className="mt-2 text-sm text-destructive">{errors.issue_creation}</p>}
          <p className="mt-2 text-sm text-muted-foreground">
            Never by default. Unless it is never, any item without an issue offers Create issue on the incident page and
            on its message in Slack. Each issue carries the item&apos;s title, the incident&apos;s identifier and a link back
            to the incident, and the activity log names whoever made the item.
          </p>
        </div>

        {chosen && chosen.fields.length > 0 && (
          <div className="flex max-w-prose flex-col gap-4">
            {chosen.fields.map((field) => (
              <div key={field.key}>
                <Label htmlFor={`issue-target-${field.key}`} className="text-foreground">
                  {field.label}
                </Label>
                <Input
                  id={`issue-target-${field.key}`}
                  className="mt-2 w-72"
                  placeholder={field.placeholder}
                  value={state.target[field.key] ?? ""}
                  onChange={(event) => changeTarget(field.key, event.target.value)}
                />
                <p className="mt-2 text-sm text-muted-foreground">{field.hint}</p>
              </div>
            ))}
          </div>
        )}

        {hasTracker && (
          <div className="max-w-prose">
            <Label htmlFor="issue-webhook-secret" className="text-foreground">
              Changes made in the tracker
            </Label>
            {savedTracker && settings.issueWebhookAutomatic ? (
              <>
                <p className="mt-1 text-sm text-muted-foreground">
                  {settings.issueWebhookRegistered
                    ? "Firefight registered the tracker's webhook itself, so changes made there reach it. Choosing another tracker or removing the connection takes the webhook away again."
                    : "Firefight registers the tracker's webhook itself when you save."}
                </p>
                {settings.issueWebhookBlockedReason && (
                  <p className="mt-2 text-sm text-destructive">{settings.issueWebhookBlockedReason}</p>
                )}
              </>
            ) : savedTracker && webhookUrl ? (
              <>
                <p className="mt-1 text-sm text-muted-foreground">
                  Changes reach Firefight through the tracker&apos;s webhook, sent to this workspace&apos;s own address.
                </p>
                <Button
                  variant="outline"
                  size="sm"
                  className="mt-2 h-8 max-w-full gap-1.5 font-mono text-xs"
                  onClick={copyAddress}
                >
                  {copied ? <IconCheck className="size-3.5 shrink-0" /> : <IconCopy className="size-3.5 shrink-0" />}
                  <span className="truncate">{webhookUrl}</span>
                </Button>
                <ol className="mt-3 list-decimal space-y-1 pl-5 text-sm text-muted-foreground">
                  {chosen?.steps.map((step) => (
                    <li key={step}>{step}</li>
                  ))}
                </ol>
                <Input
                  id="issue-webhook-secret"
                  type="password"
                  autoComplete="off"
                  className="mt-3 w-72"
                  placeholder={settings.issueWebhookSecretSet ? "Saved. Paste a new one to replace it" : "Signing secret"}
                  value={state.secret}
                  onChange={changeSecret}
                />
                {settings.issueWebhookBlockedReason && (
                  <p className="mt-2 text-sm text-destructive">{settings.issueWebhookBlockedReason}</p>
                )}
                <p className="mt-2 text-sm text-muted-foreground">
                  Firefight accepts a change only when the tracker signed it with this secret, and the secret is never
                  shown again. A change is applied as Firefight&apos;s issue sync and is in the activity log.
                </p>
              </>
            ) : (
              <p className="mt-1 text-sm text-muted-foreground">
                Save to see how to send this tracker&apos;s changes to Firefight.
              </p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
