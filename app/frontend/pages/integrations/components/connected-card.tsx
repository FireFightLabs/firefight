import { useState } from "react";
import { router } from "@inertiajs/react";

import type { EnvironmentOption, Integration } from "@/types/serializers";
import type { IntegrationProvider } from "@/types/serializers";
import { INTEGRATION_KINDS } from "@/lib/constants";
import {
  chooseIntegrationPath,
  retargetEnvironmentIntegrationPath,
  setAllToolsIntegrationPath,
  syncIntegrationPath,
  toggleToolIntegrationPath,
} from "@/lib/routes";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  EnvironmentSelect,
  toEnvironmentId,
} from "@/components/integrations/environment-select";
import { ProviderMark } from "@/components/integrations/provider-mark";
import { CodeChanges } from "@/pages/integrations/components/code-changes";
import { DisconnectDialog } from "@/pages/integrations/components/disconnect-dialog";
import { InstallationStopped } from "@/pages/integrations/components/installation-stopped";
import { LiveUpdates } from "@/pages/integrations/components/live-updates";
import { RepositorySetups } from "@/pages/integrations/components/repository-setups";
import { ScopeChoice } from "@/pages/integrations/components/scope-choice";
import { Blocked } from "@/components/blocked-tooltip";

type Environment = Integration["environments"][number];
type HealthStatus = Environment["healthStatus"];
type EnvironmentSettings = Environment["settings"];

function lackingWords(count: number, appName: string, providerName: string) {
  const owner = `An owner of the account grants them in the app's settings on ${providerName}.`;
  if (count === 1) {
    return `1 switched-on tool needs a permission the ${appName} was not granted, so it says so instead of running. ${owner}`;
  }
  return `${count} switched-on tools need permissions the ${appName} was not granted, so they say so instead of running. ${owner}`;
}

// The settings pages of the installations a switched-on tool lacks permissions on, one each, named by the account
// each was installed on so two of them can be told apart.
function permissionPages(integration: Integration, providerName: string) {
  const pages = new Map<string, string>();
  integration.environments.forEach((environment) => {
    const page = environment.installation?.page;
    if (page && !pages.has(page)) {
      pages.set(page, environment.installation?.account ?? environment.environmentName ?? "All environments");
    }
  });
  if (pages.size === 1) {
    return [...pages.keys()].map((page) => ({ page, text: `Review permissions on ${providerName}` }));
  }
  return [...pages].map(([page, label]) => ({ page, text: `Review permissions for ${label}` }));
}

// Each failing environment's error, named by its environment once the connection has more than one.
function healthErrorsOf(integration: Integration) {
  const named = integration.environments.length > 1;
  return integration.environments.flatMap((environment) => {
    if (!environment.healthError) {
      return [];
    }
    const name = environment.environmentName ?? "All environments";
    return [{ id: environment.id, message: named ? `${name}: ${environment.healthError}` : environment.healthError }];
  });
}

// What the connection was set up with beside its credentials, such as its region and the account an environment reads.
function settingsText(settings: EnvironmentSettings) {
  return settings.map((setting) => `${setting.label} ${setting.value}`).join(", ");
}

const HEALTH_LABEL: Record<
  HealthStatus,
  { label: string; variant: "default" | "destructive" | "secondary" }
> = {
  healthy: { label: "Healthy", variant: "default" },
  failing: { label: "Failing", variant: "destructive" },
  unknown: { label: "Not checked", variant: "secondary" },
};

// Only an MCP connection discovers its tools from a server, so only it names
// the transport.
const KIND_SUFFIX: Record<Integration["kind"], string> = {
  [INTEGRATION_KINDS.MCP]: " · via MCP",
  [INTEGRATION_KINDS.HTTP]: "",
  [INTEGRATION_KINDS.NATIVE]: "",
};

export function ConnectedCard({
  integration,
  provider,
  environments,
  canManage,
  onAddConnection,
}: {
  integration: Integration;
  provider: IntegrationProvider | undefined;
  environments: EnvironmentOption[];
  canManage: boolean;
  onAddConnection?: () => void;
}) {
  const [disconnecting, setDisconnecting] = useState(false);
  const healthErrors = healthErrorsOf(integration);

  const availableTools = integration.tools.filter((tool) => tool.available);
  const enabledCount = availableTools.filter((tool) => tool.enabled).length;
  const writeEnabledCount = availableTools.filter(
    (tool) => tool.enabled && !tool.readOnly,
  ).length;
  // "Reads only" is a target state, so it is a no-op once every read is on and
  // no write is.
  const readsOnlyAlreadySet =
    writeEnabledCount === 0 &&
    availableTools.every((tool) => !tool.readOnly || tool.enabled);
  const lackingCount = availableTools.filter(
    (tool) => tool.enabled && tool.accessMissing,
  ).length;
  const providerName = provider?.name ?? integration.provider;
  const pages = permissionPages(integration, providerName);
  const appName =
    integration.environments.find((environment) => environment.installation)?.installation?.app ??
    `${providerName} app`;

  function askDisconnect() {
    setDisconnecting(true);
  }

  function stopDisconnecting() {
    setDisconnecting(false);
  }

  function setAllTools(enabled: boolean, readsOnly = false) {
    router.patch(
      setAllToolsIntegrationPath(integration.id),
      { enabled, reads_only: readsOnly },
      { preserveScroll: true },
    );
  }

  function toggleTool(toolId: string) {
    router.patch(
      toggleToolIntegrationPath(integration.id),
      { tool_id: toolId },
      { preserveScroll: true },
    );
  }

  // A value the connection learned to choose from, such as which of several datasources holds its logs.
  function choose(rowId: string, key: string, value: string) {
    router.patch(
      chooseIntegrationPath(integration.id),
      { environment_row_id: rowId, key, value },
      { preserveScroll: true },
    );
  }

  function retarget(rowId: string, value: string) {
    router.patch(
      retargetEnvironmentIntegrationPath(integration.id),
      { environment_row_id: rowId, environment_id: toEnvironmentId(value) },
      { preserveScroll: true },
    );
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-3 space-y-0">
        <div className="flex items-center gap-3">
          <ProviderMark
            providerKey={integration.provider}
            mark={provider?.mark ?? "MC"}
            color={provider?.color ?? "var(--border-strong)"}
          />
          <div>
            <CardTitle className="text-base">{integration.name}</CardTitle>
            <p className="text-muted-foreground text-xs">
              {provider?.name ?? integration.provider}
              {KIND_SUFFIX[integration.kind]}
            </p>
          </div>
        </div>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <p className="text-sm font-medium">Credentials</p>
          <div className="border-border divide-border divide-y rounded-lg border">
            {integration.environments.map((environment) => {
              const rowHealth = HEALTH_LABEL[environment.healthStatus];
              return (
                <div key={environment.id}>
                  <div className="flex items-center justify-between gap-3 px-3 py-2.5">
                    <Badge variant={rowHealth.variant} className="shrink-0">
                      {rowHealth.label}
                    </Badge>
                    {environment.settings.length > 0 && (
                      <p className="text-muted-foreground min-w-0 flex-1 truncate text-xs" title={settingsText(environment.settings)}>
                        {settingsText(environment.settings)}
                      </p>
                    )}
                    {canManage && environments.length > 0 ? (
                      <EnvironmentSelect
                        compact
                        value={environment.environmentId}
                        environments={environments}
                        onChange={(value) => retarget(environment.id, value)}
                      />
                    ) : (
                      <Badge variant="outline" className="shrink-0">
                        {environment.environmentName ?? "All environments"}
                      </Badge>
                    )}
                  </div>
                  {environment.choices.map((choice) => (
                    <div key={choice.key} className="flex items-center justify-between gap-3 px-3 pb-2.5">
                      <div className="min-w-0">
                        <p className="text-sm font-medium">{choice.label}</p>
                        <p className="text-muted-foreground text-xs">{choice.hint}</p>
                      </div>
                      <Select
                        value={choice.value ?? undefined}
                        onValueChange={(value) => choose(environment.id, choice.key, value)}
                        disabled={!canManage}
                      >
                        <SelectTrigger className="h-8 w-auto min-w-[9rem] shrink-0 text-sm" aria-label={choice.label}>
                          <SelectValue placeholder="Choose one" />
                        </SelectTrigger>
                        <SelectContent align="end">
                          {choice.options.map((option) => (
                            <SelectItem key={option.value} value={option.value}>
                              {option.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  ))}
                  {environment.scopes && (
                    <ScopeChoice
                      integrationId={integration.id}
                      rowId={environment.id}
                      scopes={environment.scopes}
                      canManage={canManage}
                    />
                  )}
                  {environment.installation?.state && (
                    <InstallationStopped
                      integration={integration}
                      environment={environment}
                      providerName={providerName}
                      canManage={canManage}
                    />
                  )}
                  {environment.liveUpdates && (
                    <LiveUpdates
                      integrationId={integration.id}
                      rowId={environment.id}
                      state={environment.liveUpdates}
                      canManage={canManage}
                    />
                  )}
                </div>
              );
            })}
          </div>
          <p className="text-muted-foreground text-xs">
            A grant scoped to an environment only matches the credentials wired
            to it.
          </p>
        </div>

        {healthErrors.length > 0 && (
          <div className="border-destructive/40 bg-destructive/10 text-destructive flex flex-col gap-1 rounded-md border px-3 py-2 text-xs">
            {healthErrors.map((error) => (
              <p key={error.id}>{error.message}</p>
            ))}
          </div>
        )}

        {lackingCount > 0 && (
          <div className="flex flex-col gap-1.5 border-warning-border bg-warning-tint rounded-md border px-3 py-2 text-xs">
            <p>{lackingWords(lackingCount, appName, providerName)}</p>
            {pages.map((entry) => (
              <a
                key={entry.page}
                href={entry.page}
                target="_blank"
                rel="noopener noreferrer"
                className="w-fit font-medium underline underline-offset-2"
              >
                {entry.text}
              </a>
            ))}
          </div>
        )}

        {integration.protectedPaths && (
          <CodeChanges
            key={integration.protectedPaths.join("\n")}
            integrationId={integration.id}
            paths={integration.protectedPaths}
            canManage={canManage}
          />
        )}

        {integration.protectedPaths && (
          <RepositorySetups integrationId={integration.id} setups={integration.setups} canManage={canManage} />
        )}

        {integration.tools.length === 0 ? (
          <p className="text-muted-foreground text-sm">
            No tools discovered yet. Refresh to pull the server's tool list.
          </p>
        ) : (
          <div className="flex flex-col">
            <div className="flex items-center justify-between gap-3 pb-1">
              <p className="text-sm font-medium">
                Capabilities{" "}
                <span className="text-muted-foreground font-normal">
                  {enabledCount} of {availableTools.length} on
                  {writeEnabledCount > 0 && `, ${writeEnabledCount} that write`}
                </span>
              </p>
              {canManage && (
                <div className="text-muted-foreground flex items-center gap-3 text-xs">
                  <button
                    type="button"
                    onClick={() => setAllTools(true, true)}
                    disabled={readsOnlyAlreadySet}
                    className="hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                  >
                    Reads only
                  </button>
                  <span aria-hidden className="bg-border h-3 w-px" />
                  <button
                    type="button"
                    onClick={() => setAllTools(true)}
                    disabled={enabledCount === availableTools.length}
                    className="hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                  >
                    Enable all
                  </button>
                  <span aria-hidden className="bg-border h-3 w-px" />
                  <button
                    type="button"
                    onClick={() => setAllTools(false)}
                    disabled={enabledCount === 0}
                    className="hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                  >
                    Disable all
                  </button>
                </div>
              )}
            </div>
            {integration.tools.map((tool) => (
              <div
                key={tool.id}
                className="border-border flex items-start justify-between gap-3 border-b py-2.5 last:border-b-0"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">{tool.name}</span>
                    {!tool.readOnly && (
                      <Badge variant="secondary" className="text-xs">
                        write
                      </Badge>
                    )}
                    {!tool.available && (
                      <Badge variant="outline" className="text-xs">
                        no longer offered
                      </Badge>
                    )}
                  </div>
                  <p
                    className="text-muted-foreground mt-0.5 line-clamp-2 text-xs"
                    title={tool.description ?? undefined}
                  >
                    {tool.description ??
                      "No description offered by the server."}
                  </p>
                  {tool.accessMissing && (
                    <p className="text-warning mt-0.5 text-xs">
                      {tool.accessMissing}
                    </p>
                  )}
                  {tool.enabled && (
                    <code className="text-fg-muted mt-1 block truncate text-[11px]">
                      {tool.actionKey}
                    </code>
                  )}
                </div>
                <Blocked reason={tool.toggleBlockedReason ?? undefined}>
                  <Switch
                    checked={tool.enabled}
                    disabled={!canManage || !tool.available}
                    onCheckedChange={() => toggleTool(tool.id)}
                    aria-label={`Toggle ${tool.name}`}
                  />
                </Blocked>
              </div>
            ))}
          </div>
        )}

        {canManage && (
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => router.post(syncIntegrationPath(integration.id))}
            >
              Refresh tools
            </Button>
            {onAddConnection && (
              <Button size="sm" variant="outline" onClick={onAddConnection}>
                Add connection
              </Button>
            )}
            <Button
              size="sm"
              variant="ghost"
              className="text-destructive"
              onClick={askDisconnect}
            >
              Disconnect
            </Button>
          </div>
        )}
        {disconnecting && (
          <DisconnectDialog integration={integration} open onClose={stopDisconnecting} />
        )}
      </CardContent>
    </Card>
  );
}
