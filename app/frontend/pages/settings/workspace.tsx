import { useState } from "react"
import { Head, Link, router, usePage } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { ARCHIVE_CHANNEL_DELAY_CHOICES, MEMORY_EXPIRY_DAY_CHOICES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { integrationsPath, settingsWorkspacePath } from "@/lib/routes"
import { AiAccountsCard, type AiSignIn } from "@/components/ai/ai-accounts-card"
import type { AiCredits } from "@/components/ai/ai-credits-row"
import {
  IssueTrackingCard,
  trackerChoice,
  trackerSlug,
  type IssueTrackingState,
} from "@/pages/settings/components/workspace/issue-tracking-card"
import type { AiProviderOption, WorkspaceAiAccount, WorkspaceSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface WorkspacePageProps extends SharedProps {
  settings: WorkspaceSettings
  issueWebhookUrl: string | null
  aiAccounts: WorkspaceAiAccount[]
  aiProviders: AiProviderOption[]
  aiSignIn: AiSignIn | null
  aiFallback: string
  aiCredits: AiCredits | null
}

function retentionText(days?: number): string {
  return days ? String(days) : ""
}

// No window is a choice of its own in the picker, sent as an empty value the server saves as none.
const MEMORIES_KEPT = "kept"

function expiryChoice(days?: number): string {
  return days ? String(days) : MEMORIES_KEPT
}

function expiryDays(choice: string): string {
  return choice === MEMORIES_KEPT ? "" : choice
}

// Firefight's own agent is no connection, and a connection's slug never holds a hyphen, so this never names one.
const FIREFIGHT_WRITES = "firefight-own-agent"

function agentChoice(slug: string | null | undefined): string {
  return slug ?? FIREFIGHT_WRITES
}

function agentSlug(choice: string): string {
  return choice === FIREFIGHT_WRITES ? "" : choice
}

export default function Workspace() {
  const { settings, issueWebhookUrl, aiAccounts, aiProviders, aiSignIn, aiFallback, aiCredits } = usePage<WorkspacePageProps>().props
  const canManageAiAccounts = useCan("ai_accounts")
  const [transcriptAccess, setTranscriptAccess] = useState(settings.transcriptAccessEnabled)
  const [retention, setRetention] = useState(retentionText(settings.transcriptRetentionDays))
  const [archiveDelay, setArchiveDelay] = useState(settings.archiveChannelDelay)
  const [webSearch, setWebSearch] = useState(settings.webSearchEnabled)
  const [regression, setRegression] = useState(settings.halonRegressionEnabled)
  const [memoryExpiry, setMemoryExpiry] = useState(expiryChoice(settings.memoryExpiryDays))
  const [codeFixAgent, setCodeFixAgent] = useState(agentChoice(settings.codeFixAgent))
  const connectedAgents = settings.codeFixAgents.length > 1
  const [issueTracking, setIssueTracking] = useState<IssueTrackingState>({
    tracker: trackerChoice(settings.issueTracker),
    creation: settings.issueCreation,
    target: settings.issueTrackerTarget,
    secret: "",
  })
  const [saving, setSaving] = useState(false)
  const [errors, setErrors] = useState<Errors>({})

  function changeRetention(event: React.ChangeEvent<HTMLInputElement>) {
    setRetention(event.target.value)
  }

  function finish() {
    setSaving(false)
  }

  // The secret is never sent back, so the field empties once it is saved.
  function succeed() {
    setErrors({})
    setIssueTracking((current) => ({ ...current, secret: "" }))
  }

  function fail(formErrors: Errors) {
    setErrors(formErrors)
  }

  function save() {
    setSaving(true)
    router.patch(
      settingsWorkspacePath(),
      {
        transcript_access_enabled: transcriptAccess,
        transcript_retention_days: retention,
        archive_channel_delay: archiveDelay,
        web_search_enabled: webSearch,
        halon_regression_enabled: regression,
        memory_expiry_days: expiryDays(memoryExpiry),
        code_fix_agent: agentSlug(codeFixAgent),
        issue_tracker: trackerSlug(issueTracking.tracker),
        issue_creation: issueTracking.creation,
        issue_tracker_target: issueTracking.target,
        issue_webhook_secret: issueTracking.secret,
      },
      { preserveScroll: true, onSuccess: succeed, onError: fail, onFinish: finish },
    )
  }

  return (
    <AuthenticatedLayout title="Workspace">
      <Head title="Workspace" />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <CardTitle>Incident conversations</CardTitle>
            <CardDescription className="mt-1">
              What people say in an incident channel is stored so Firefight can summarise it, note
              what was worked out onto the timeline, and draft a postmortem from it. These two
              settings decide who else can read it and how long it is kept.
            </CardDescription>
          </CardHeader>

          <CardContent className="flex flex-col gap-6">
            <div className="flex items-start justify-between gap-6">
              <div className="max-w-prose">
                <Label htmlFor="transcript-access" className="text-foreground">
                  Let AI agents read incident conversations
                </Label>
                <p className="mt-1 text-sm text-muted-foreground">
                  Off by default. When this is on, a person or an agent holding the Incident
                  Transcripts ability can read the messages of an incident over the API and MCP.
                  Secrets matching known token formats are redacted before anything is stored,
                  but names, customers and links are not, so this is the rawest data in the
                  workspace.
                </p>
              </div>
              <Switch
                id="transcript-access"
                checked={transcriptAccess}
                onCheckedChange={setTranscriptAccess}
              />
            </div>

            <div className="max-w-prose">
              <Label htmlFor="transcript-retention" className="text-foreground">
                Keep conversations for
              </Label>
              <div className="mt-2 flex items-center gap-2">
                <Input
                  id="transcript-retention"
                  type="number"
                  min={1}
                  value={retention}
                  onChange={changeRetention}
                  placeholder="Forever"
                  className="w-28"
                />
                <span className="text-sm text-muted-foreground">days after an incident ends</span>
              </div>
              {errors.transcript_retention_days && (
                <p className="mt-2 text-sm text-destructive">{errors.transcript_retention_days}</p>
              )}
              <p className="mt-2 text-sm text-muted-foreground">
                Leave it empty to keep them for good. What the team worked out survives either
                way, as timeline notes with the quote and the person, and in the postmortem, so
                clearing the messages loses the conversation and not the record.
              </p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Incident channels</CardTitle>
            <CardDescription className="mt-1">
              When an incident is resolved or cancelled, Firefight can archive its channel so it
              stops taking up room in the sidebar. The messages stay in the channel and the
              incident keeps its timeline.
            </CardDescription>
          </CardHeader>

          <CardContent>
            <div className="max-w-prose">
              <Label htmlFor="archive-channel-delay" className="text-foreground">
                Archive the channel
              </Label>
              <div className="mt-2 flex items-center gap-2">
                <Select value={archiveDelay} onValueChange={setArchiveDelay}>
                  <SelectTrigger id="archive-channel-delay" className="w-40">
                    <SelectValue placeholder="Choose a delay" />
                  </SelectTrigger>
                  <SelectContent>
                    {ARCHIVE_CHANNEL_DELAY_CHOICES.map((choice) => (
                      <SelectItem key={choice.value} value={choice.value}>
                        {choice.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <span className="text-sm text-muted-foreground">after the incident ends</span>
              </div>
              {errors.archive_channel_delay && (
                <p className="mt-2 text-sm text-destructive">{errors.archive_channel_delay}</p>
              )}
              <p className="mt-2 text-sm text-muted-foreground">
                Reopening an incident unarchives its channel. A change here applies to incidents
                that end after you save, so one that is already resolved keeps the delay it was
                given.
              </p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Halon</CardTitle>
          </CardHeader>

          <CardContent className="flex flex-col gap-6">
            <div className="flex items-start justify-between gap-6">
              <div className="max-w-prose">
                <Label htmlFor="web-search" className="text-foreground">
                  Let Halon search the web
                </Label>
                <p className="mt-1 text-sm text-muted-foreground">
                  On by default. Halon and the agent that writes code fixes can search and read public web
                  pages through Firefight, such as a library&apos;s documentation or a provider&apos;s status
                  page, and cite what they used. A search never carries anything that looks like a credential.
                  Turn it off and they work only from what your connections and code show.
                </p>
              </div>
              <Switch id="web-search" checked={webSearch} onCheckedChange={setWebSearch} />
            </div>

            <div className="flex items-start justify-between gap-6">
              <div className="max-w-prose">
                <Label htmlFor="halon-regression" className="text-foreground">
                  Let Firefight test Halon on your rated answers
                </Label>
                <p className="mt-1 text-sm text-muted-foreground">
                  Off by default. When this is on, Firefight replays Halon&apos;s past investigations whose answer
                  your team confirmed or marked wrong, to check that a new version of Halon still gets them right.
                  A replay uses only what Halon read at the time, so it reads nothing new from your systems and posts
                  nothing. Only Firefight&apos;s staff see the results. Turn it off and none are replayed again.
                </p>
              </div>
              <Switch id="halon-regression" checked={regression} onCheckedChange={setRegression} />
            </div>

            <div className="max-w-prose">
              <Label htmlFor="memory-expiry" className="text-foreground">
                Stop using unconfirmed memories
              </Label>
              <div className="mt-2">
                <Select value={memoryExpiry} onValueChange={setMemoryExpiry}>
                  <SelectTrigger id="memory-expiry" className="w-72">
                    <SelectValue placeholder="Choose when" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={MEMORIES_KEPT}>Never, use them until someone decides</SelectItem>
                    {MEMORY_EXPIRY_DAY_CHOICES.map((days) => (
                      <SelectItem key={days} value={String(days)}>
                        After {days} days without a confirmation
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              {errors.memory_expiry_days && <p className="mt-2 text-sm text-destructive">{errors.memory_expiry_days}</p>}
              <p className="mt-2 text-sm text-muted-foreground">
                Halon uses what it learns at once, marked unconfirmed until a person confirms it. Choose a window and a
                memory nobody confirms in time expires. Halon stops using it, and it moves to Expired on the Memory page,
                where anyone can still confirm it. One Halon learns again starts waiting afresh.
              </p>
            </div>

            <div className="max-w-prose">
              <Label htmlFor="code-fix-agent" className="text-foreground">
                Write code fixes with
              </Label>
              <div className="mt-2">
                <Select value={codeFixAgent} onValueChange={setCodeFixAgent}>
                  <SelectTrigger id="code-fix-agent" className="w-72">
                    <SelectValue placeholder="Choose who writes code fixes" />
                  </SelectTrigger>
                  <SelectContent>
                    {settings.codeFixAgents.map((choice) => (
                      <SelectItem key={agentChoice(choice.value)} value={agentChoice(choice.value)}>
                        {choice.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              {errors.code_fix_agent && <p className="mt-2 text-sm text-destructive">{errors.code_fix_agent}</p>}
              {settings.codeFixAgentBlockedReason && (
                <p className="mt-2 text-sm text-destructive">{settings.codeFixAgentBlockedReason}</p>
              )}
              <p className="mt-2 text-sm text-muted-foreground">
                Firefight&apos;s own agent writes a fix&apos;s code change in Firefight&apos;s sandbox and opens the pull
                request through your code host connection. Pick a coding agent you connected and Firefight hands it the
                change and the evidence instead. That agent opens the pull request itself, and the fix shows how it is
                going until it finishes or hits its time limit. Both go through your permissions and approval rules.
                An investigation never starts a code fix on its own.
              </p>
              {!connectedAgents && (
                <p className="mt-2 text-sm text-muted-foreground">
                  No coding agent is connected yet. Connect one under{" "}
                  <Link href={integrationsPath()} className="underline underline-offset-4">
                    Integrations
                  </Link>{" "}
                  to choose it here.
                </p>
              )}
            </div>
          </CardContent>
        </Card>

        <AiAccountsCard
          accounts={aiAccounts}
          providers={aiProviders}
          signIn={aiSignIn}
          fallback={aiFallback}
          credits={aiCredits}
          canManage={canManageAiAccounts}
        />

        <IssueTrackingCard
          settings={settings}
          webhookUrl={issueWebhookUrl}
          state={issueTracking}
          errors={errors}
          onChange={setIssueTracking}
        />

        <div>
          <Button onClick={save} disabled={saving}>
            Save changes
          </Button>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
