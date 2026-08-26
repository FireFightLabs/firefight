import { useState } from "react"
import { Head, router, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { settingsWorkspacePath } from "@/lib/routes"
import type { WorkspaceSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface WorkspacePageProps extends SharedProps {
  settings: WorkspaceSettings
}

// A blank retention means keep everything, so the field is empty rather than
// carrying a number that would read as a limit.
function retentionText(days?: number): string {
  return days ? String(days) : ""
}

export default function Workspace() {
  const { settings } = usePage<WorkspacePageProps>().props
  const [transcriptAccess, setTranscriptAccess] = useState(settings.transcriptAccessEnabled)
  const [retention, setRetention] = useState(retentionText(settings.transcriptRetentionDays))
  const [saving, setSaving] = useState(false)

  function changeRetention(event: React.ChangeEvent<HTMLInputElement>) {
    setRetention(event.target.value)
  }

  function finish() {
    setSaving(false)
  }

  function save() {
    setSaving(true)
    router.patch(
      settingsWorkspacePath(),
      { transcript_access_enabled: transcriptAccess, transcript_retention_days: retention },
      { preserveScroll: true, onFinish: finish },
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
              <p className="mt-2 text-sm text-muted-foreground">
                Leave it empty to keep them for good. What the team worked out survives either
                way, as timeline notes with the quote and the person, and in the postmortem, so
                clearing the messages loses the conversation and not the record.
              </p>
            </div>
          </CardContent>
        </Card>

        <div>
          <Button onClick={save} disabled={saving}>
            Save changes
          </Button>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
