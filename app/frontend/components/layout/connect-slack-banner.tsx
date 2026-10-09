import { router, usePage } from "@inertiajs/react";
import { IconPlugConnected } from "@tabler/icons-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { useCan } from "@/lib/permissions";
import { onboardingConnectSlackPath } from "@/lib/routes";

function connectSlack() {
  router.post(onboardingConnectSlackPath());
}

// The workspace started without Slack. Everything but incidents works, so the page says what waits on it.
export function ConnectSlackBanner() {
  const { currentWorkspace } = usePage().props;
  const canConnect = useCan("workspace");

  if (!currentWorkspace || currentWorkspace.chatConnected) {
    return null;
  }

  return (
    <Alert className="mx-6 mt-6 w-auto flex flex-col items-start justify-between gap-3 border-border edge-bar [--edge-bar:var(--lime)] bg-surface-card text-fg-primary sm:flex-row sm:items-center *:data-[slot=alert-description]:text-fg-body">
      <div className="flex items-start gap-3">
        <IconPlugConnected className="mt-0.5 size-5 shrink-0 text-brand" />
        <div>
          <AlertTitle>Connect Slack to run incidents</AlertTitle>
          <AlertDescription>
            Each incident gets its own Slack channel, so declaring one waits
            until Slack is connected. Everything else works now.
          </AlertDescription>
        </div>
      </div>
      {canConnect ? (
        <Button variant="outline" size="sm" className="shrink-0" onClick={connectSlack}>
          Connect Slack
        </Button>
      ) : (
        <span className="text-xs shrink-0 text-fg-secondary">
          Ask a workspace admin to connect it.
        </span>
      )}
    </Alert>
  );
}
