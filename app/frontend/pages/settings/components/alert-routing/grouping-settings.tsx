import { useState } from "react"
import { router } from "@inertiajs/react"

import type { AlertRoutingPolicy } from "@/types/serializers"
import { alertRoutingPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

const MIN_WINDOW_MINUTES = 5
const MAX_WINDOW_MINUTES = 10080

export function GroupingSettings({
  policy,
  alertSourceId,
}: {
  policy: AlertRoutingPolicy
  alertSourceId: string | null
}) {
  const [windowMinutes, setWindowMinutes] = useState(String(policy.groupingWindowMinutes))
  const [matchFields, setMatchFields] = useState(policy.contentMatchFields.join(", "))
  const [errors, setErrors] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const dirty =
    windowMinutes !== String(policy.groupingWindowMinutes) ||
    matchFields !== policy.contentMatchFields.join(", ")

  function save() {
    setErrors([])
    setSaving(true)
    setSaved(false)
    router.patch(
      alertRoutingPath(),
      {
        alert_source_id: alertSourceId,
        policy: {
          grouping_window_minutes: Number(windowMinutes),
          content_match_fields: matchFields.split(",").map((f) => f.trim()).filter(Boolean),
        },
      },
      {
        onSuccess: () => setSaved(true),
        onError: (errorBag: Record<string, string | string[]>) => setErrors(Object.values(errorBag).flat()),
        onFinish: () => setSaving(false),
      }
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Grouping</CardTitle>
        <CardDescription className="mt-1">
          Alerts whose grouping fields match within the window attach to the same incident instead of
          creating new ones.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex flex-wrap items-end gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="grouping-window">Window (minutes)</Label>
            <Input
              id="grouping-window"
              type="number"
              min={MIN_WINDOW_MINUTES}
              max={MAX_WINDOW_MINUTES}
              value={windowMinutes}
              onChange={(e) => setWindowMinutes(e.target.value)}
              className="w-32"
            />
          </div>
          <div className="flex min-w-64 flex-1 flex-col gap-2">
            <Label htmlFor="grouping-fields">Group by fields</Label>
            <Input
              id="grouping-fields"
              value={matchFields}
              onChange={(e) => setMatchFields(e.target.value)}
              placeholder="service"
            />
          </div>
          <Button size="sm" onClick={save} disabled={saving || !dirty}>
            {saved && !dirty ? "Saved" : "Save"}
          </Button>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Comma-separated alert fields; two alerts group when all of these values match. 5 minutes to 7 days.
        </p>
        {errors.length > 0 && (
          <div className="mt-3 rounded-md border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive">
            {errors.map((message, i) => (
              <p key={i}>{message}</p>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
