import type { Integration } from "@/types/serializers";
import { INSTALLATION_STATES } from "@/lib/generated/constants";
import { oauthStartIntegrationsPath } from "@/lib/routes";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

type Environment = Integration["environments"][number];

// Installing the provider's app again for this environment comes back to the same connection, since it keeps its name.
function reconnectHref(integration: Integration, environment: Environment) {
  const params = new URLSearchParams({ provider: integration.provider, name: integration.name });
  if (environment.environmentId) {
    params.set("environment_id", environment.environmentId);
  }
  return `${oauthStartIntegrationsPath()}?${params.toString()}`;
}

// What a person does about an installation the provider says stopped: install it again once it was removed, or fix it in
// the app's settings at the provider.
export function InstallationStopped({
  integration,
  environment,
  providerName,
  canManage,
}: {
  integration: Integration;
  environment: Environment;
  providerName: string;
  canManage: boolean;
}) {
  const installation = environment.installation;
  if (!installation) {
    return null;
  }
  const removed = installation.state === INSTALLATION_STATES.REMOVED;

  return (
    <div className="flex flex-col gap-1.5 px-3 pb-2.5">
      <Badge variant="destructive" className="w-fit">
        {installation.label}
      </Badge>
      <p className="text-muted-foreground text-xs">{installation.reason}</p>
      {canManage && removed && (
        <Button asChild size="sm" variant="outline" className="h-8 w-fit">
          <a href={reconnectHref(integration, environment)}>Reconnect</a>
        </Button>
      )}
      {canManage && !removed && installation.page && (
        <Button asChild size="sm" variant="outline" className="h-8 w-fit">
          <a href={installation.page} target="_blank" rel="noopener noreferrer">
            Open {providerName}
          </a>
        </Button>
      )}
    </div>
  );
}
