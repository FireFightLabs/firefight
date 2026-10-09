import { usePage } from "@inertiajs/react";
import { IconPlugConnectedX } from "@tabler/icons-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { onboardingReinstallPath } from "@/lib/routes";

// Slack said the install is gone. Recorded data stays readable, so the page
// keeps working and asks an admin to reconnect instead of locking anyone out.
export function DisconnectedBanner() {
  const { currentWorkspace, currentUserIsAdmin } = usePage().props;

  if (!currentWorkspace?.disconnected) {
    return null;
  }

  return (
    <Alert
      variant="destructive"
      className="mx-6 mt-6 w-auto flex items-center justify-between gap-4 border-border edge-bar [--edge-bar:var(--error)] bg-error-tint text-fg-primary *:data-[slot=alert-description]:text-fg-body"
    >
      <div className="flex items-start gap-3">
        <IconPlugConnectedX className="mt-0.5 size-5 shrink-0 text-error" />
        <div>
          <AlertTitle>Slack is disconnected</AlertTitle>
          <AlertDescription>
            Firefight can no longer reach {currentWorkspace.name} in Slack.
            Incidents, settings and history are still here, but nothing will
            post to Slack until the app is reinstalled.
          </AlertDescription>
        </div>
      </div>
      {currentUserIsAdmin ? (
        <Button asChild variant="outline" size="sm" className="shrink-0">
          <a href={onboardingReinstallPath()}>Reconnect Slack</a>
        </Button>
      ) : (
        <span className="text-xs shrink-0 text-fg-secondary">
          Ask a workspace admin to reconnect it.
        </span>
      )}
    </Alert>
  );
}
