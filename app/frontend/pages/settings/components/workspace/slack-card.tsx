import { useState } from "react"
import { router, usePage } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { onboardingConnectSlackPath, reinstallSlackPath } from "@/lib/routes"

interface SlackCardProps {
  teamName: string | null | undefined
}

function connectSlack() {
  router.post(onboardingConnectSlackPath())
}

function slackDescription(teamName: string | null | undefined, connected: boolean, disconnected: boolean) {
  if (!connected) {
    return "Slack is not connected yet. Each incident gets its own Slack channel, so declaring one waits until it is."
  }
  if (disconnected) {
    return `Firefight can no longer reach ${teamName} in Slack. Reinstall to reconnect it. Incidents, settings and history stay as they are.`
  }
  return `Firefight is connected to ${teamName} in Slack. Reinstall to give Firefight new Slack permissions after an update, without disconnecting. Channels, incidents and settings stay as they are.`
}

// Pressing Reinstall leaves for Slack, so the button stays busy unless the server answers here instead.
export function SlackCard({ teamName }: SlackCardProps) {
  const { currentWorkspace } = usePage().props
  const [leaving, setLeaving] = useState(false)
  const connected = currentWorkspace?.chatConnected ?? false
  const disconnected = currentWorkspace?.disconnected ?? false

  function stayHere() {
    setLeaving(false)
  }

  function reinstall() {
    setLeaving(true)
    router.post(reinstallSlackPath(), {}, { onSuccess: stayHere, onError: stayHere })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Slack</CardTitle>
        <CardDescription className="mt-1 max-w-prose">
          {slackDescription(teamName, connected, disconnected)}
        </CardDescription>
      </CardHeader>

      <CardContent>
        {connected ? (
          <Button variant="outline" onClick={reinstall} disabled={leaving}>
            Reinstall Slack
          </Button>
        ) : (
          <Button variant="outline" onClick={connectSlack}>
            Connect Slack
          </Button>
        )}
      </CardContent>
    </Card>
  )
}
