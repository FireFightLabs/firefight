import { useState } from "react";
import { router } from "@inertiajs/react";
import { IconArrowLeft } from "@tabler/icons-react";

import type {
  EnvironmentOption,
  IntegrationProvider,
} from "@/types/serializers";
import { CUSTOM_MCP_PROVIDER_KEY, INTEGRATION_KINDS } from "@/lib/constants";
import { integrationsPath, oauthStartIntegrationsPath } from "@/lib/routes";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  ALL_ENVIRONMENTS,
  EnvironmentSelect,
  toEnvironmentId,
} from "@/components/integrations/environment-select";
import { ProviderMark } from "@/components/integrations/provider-mark";
import { ConnectionUrlForm } from "@/components/integrations/connection-url-form";
import { CredentialsForm } from "@/components/integrations/credentials-form";
import {
  appendConnectValues,
  ConnectFields,
  connectFieldsComplete,
  type ConnectValue,
  type ConnectValues,
} from "@/components/integrations/connect-fields";
import { defaultRegion, RegionSelect } from "@/components/integrations/region-select";
import { INTEGRATION_CONNECT_WITH } from "@/lib/generated/constants";
import { whenClosed } from "@/lib/handlers";

interface OauthStart {
  providerKey: string;
  kind?: string;
  name: string;
  environmentId: string;
  region: string;
  fields: ConnectValues;
  returnTo?: string;
}

function oauthHref({ providerKey, kind, name, environmentId, region, fields, returnTo }: OauthStart) {
  const params = new URLSearchParams({ provider: providerKey });
  if (kind) {
    params.set("kind", kind);
  }
  if (returnTo) {
    params.set("return_to", returnTo);
  }
  if (name) {
    params.set("name", name);
  }
  const environment = toEnvironmentId(environmentId);
  if (environment) {
    params.set("environment_id", environment);
  }
  if (region) {
    params.set("region", region);
  }
  appendConnectValues(params, fields);
  return `${oauthStartIntegrationsPath()}?${params.toString()}`;
}

// returnTo is the dashboard page to come back to once connected, such as the chat the dialog was opened from.
export function ConnectDialog({
  provider,
  environments,
  existingNames,
  returnTo,
  onDismiss,
}: {
  provider: IntegrationProvider | null;
  environments: EnvironmentOption[];
  existingNames: string[];
  returnTo?: string;
  onDismiss: () => void;
}) {
  // Keyed on the provider so a different tile mounts a fresh form. The last provider
  // is kept so the content stays put through the close animation.
  const [shownProvider, setShownProvider] = useState(provider);
  if (provider && provider !== shownProvider) {
    setShownProvider(provider);
  }

  return (
    <Dialog open={provider !== null} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-md">
        {shownProvider && (
          <ConnectForm
            key={shownProvider.key}
            provider={shownProvider}
            environments={environments}
            existingNames={existingNames}
            returnTo={returnTo}
            onDismiss={onDismiss}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ConnectForm({
  provider,
  environments,
  existingNames,
  returnTo,
  onDismiss,
}: {
  provider: IntegrationProvider;
  environments: EnvironmentOption[];
  existingNames: string[];
  returnTo?: string;
  onDismiss: () => void;
}) {
  const [name, setName] = useState(
    provider.key === CUSTOM_MCP_PROVIDER_KEY ? "" : provider.name,
  );
  const [serverUrl, setServerUrl] = useState(provider.serverUrl);
  const [authorization, setAuthorization] = useState("");
  const [environmentId, setEnvironmentId] = useState(ALL_ENVIRONMENTS);
  const [submitting, setSubmitting] = useState(false);
  const [useToken, setUseToken] = useState(false);
  const [separateAccount, setSeparateAccount] = useState(false);
  const [useMcpServer, setUseMcpServer] = useState(false);
  const [region, setRegion] = useState(defaultRegion(provider));
  const [fields, setFields] = useState<ConnectValues>({});
  const regional = provider.regions.length > 1;
  // A native provider's fields are its own connection's, so reaching its MCP server instead asks none. The token form
  // takes the server's whole address, so it does not ask the fields that are part of it.
  const oauthFields = useMcpServer ? [] : provider.connectFields;
  const tokenFields = oauthFields.filter((field) => !field.address);
  const oauthFieldsComplete = connectFieldsComplete(oauthFields, fields);
  const tokenFieldsComplete = connectFieldsComplete(tokenFields, fields);

  const connectsWithUrl = provider.connectWith === INTEGRATION_CONNECT_WITH.CONNECTION_URL;
  const connectsWithCredentials = provider.connectWith === INTEGRATION_CONNECT_WITH.API_TOKEN;
  // A provider connected with credentials may also be reached through its own MCP server.
  const showCredentials = connectsWithCredentials && !useMcpServer;
  const nativeConnect = provider.kind === INTEGRATION_KINDS.NATIVE && !connectsWithUrl && !connectsWithCredentials;
  const oauthAvailable = nativeConnect || provider.serverUrl !== "";
  const showOauth = oauthAvailable && !useToken && !connectsWithUrl && !showCredentials;
  const showManualForm = connectsWithUrl ? useToken : (!oauthAvailable || useToken) && !nativeConnect && !showCredentials;
  const mcpKind = useMcpServer ? INTEGRATION_KINDS.MCP : undefined;
  const showSecondAccountLink = !separateAccount;
  const showTokenLink = !nativeConnect;
  const alreadyConnected = existingNames.length > 0;
  const nameTaken = separateAccount && existingNames.includes(name.trim());

  function switchToMcpServer() {
    setUseToken(true);
  }

  function switchToProviderServer() {
    setUseMcpServer(true);
  }

  function backToCredentials() {
    setUseMcpServer(false);
    setUseToken(false);
  }

  function setField(key: string, value: ConnectValue) {
    setFields((current) => ({ ...current, [key]: value }));
  }

  // Each region has its own server, so choosing one in the token form fills in its address.
  function chooseRegion(key: string) {
    setRegion(key);
    const chosen = provider.regions.find((each) => each.key === key);
    if (chosen) {
      setServerUrl(chosen.serverUrl);
    }
  }

  function toggleSeparateAccount() {
    const next = !separateAccount;
    setSeparateAccount(next);
    setName(next ? "" : provider.name);
  }

  function submit() {
    setSubmitting(true);
    router.post(
      integrationsPath(),
      {
        provider: provider.key,
        name,
        server_url: serverUrl,
        authorization,
        environment_id: toEnvironmentId(environmentId),
        fields,
        return_to: returnTo,
      },
      { onFinish: () => onDismiss() },
    );
  }

  return (
    <>
      <DialogHeader className="items-center gap-0 text-center sm:text-center">
        <ProviderMark
          providerKey={provider.key}
          mark={provider.mark}
          color={provider.color}
          size={52}
        />
        <DialogTitle className="mt-3 text-lg">
          {alreadyConnected
            ? `Add a ${provider.name} connection`
            : `Connect ${provider.name}`}
        </DialogTitle>
        <DialogDescription className="mx-auto max-w-xs leading-relaxed">
          {showCredentials
            ? alreadyConnected
              ? "Use the same name to add an environment or replace its credentials, or a new name for another account."
              : "Enter credentials for each environment. What Halon can read and change is what their role allows."
            : connectsWithUrl
            ? alreadyConnected
              ? "Use the same name to add an environment or replace its URL, or a new name for another database."
              : "Paste a connection URL for each environment. Halon reads tables, runs read-only queries and sees what the database is doing."
            : alreadyConnected
            ? "Authorize another environment on the connection you have, or name this one to keep a second account's permissions separate."
            : nativeConnect
              ? "Install the Firefight app, choose what it can reach, and pick which tools to enable. Nothing turns on automatically."
              : "Firefight discovers this server's tools and you pick which to enable. Nothing turns on automatically."}
        </DialogDescription>
      </DialogHeader>

      {showCredentials && (
        <CredentialsForm
          provider={provider}
          environments={environments}
          returnTo={returnTo}
          onDismiss={onDismiss}
          onUseMcpServer={provider.mcpAlternative ? switchToProviderServer : undefined}
        />
      )}

      {connectsWithUrl && !useToken && (
        <ConnectionUrlForm
          provider={provider}
          environments={environments}
          returnTo={returnTo}
          onDismiss={onDismiss}
          onUseMcpServer={switchToMcpServer}
        />
      )}

      {showOauth && (
        <div className="flex flex-col gap-4 pt-1">
          {useMcpServer && (
            <button
              type="button"
              onClick={backToCredentials}
              className="text-muted-foreground hover:text-foreground -mt-1 flex items-center gap-1 self-start text-xs"
            >
              <IconArrowLeft className="size-3.5" />
              Back to credentials
            </button>
          )}
          {(environments.length > 0 || separateAccount || regional || oauthFields.length > 0) && (
            <div className="border-border divide-border divide-y rounded-lg border">
              {environments.length > 0 && (
                <div className="flex items-center justify-between gap-3 px-3 py-2.5">
                  <div className="min-w-0">
                    <p className="text-sm font-medium">Environment</p>
                    <p className="text-muted-foreground text-xs">
                      Which one these credentials reach
                    </p>
                  </div>
                  <EnvironmentSelect
                    compact
                    value={environmentId}
                    environments={environments}
                    onChange={setEnvironmentId}
                  />
                </div>
              )}

              {regional && (
                <div className="flex items-center justify-between gap-3 px-3 py-2.5">
                  <div className="min-w-0">
                    <p className="text-sm font-medium">Region</p>
                    <p className="text-muted-foreground text-xs">
                      Where your {provider.name} account is
                    </p>
                  </div>
                  <RegionSelect compact value={region} regions={provider.regions} onChange={setRegion} />
                </div>
              )}

              <ConnectFields compact fields={oauthFields} values={fields} onChange={setField} />

              {separateAccount && (
                <div className="flex flex-col gap-1.5 px-3 py-2.5">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-sm font-medium">Connection name</p>
                      <p className="text-muted-foreground text-xs">
                        Keeps its permissions separate from {provider.name}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={toggleSeparateAccount}
                      className="text-muted-foreground hover:text-foreground shrink-0 text-xs"
                    >
                      Remove
                    </button>
                  </div>
                  <Input
                    autoFocus
                    value={name}
                    onChange={(event) => setName(event.target.value)}
                    placeholder={`e.g. ${provider.name} Payments`}
                    className="h-8"
                  />
                  {nameTaken && (
                    <p className="text-destructive text-xs">
                      You already have a connection with this name.
                    </p>
                  )}
                </div>
              )}
            </div>
          )}

          <div className="flex flex-col gap-2">
            {(separateAccount && (!name.trim() || nameTaken)) || !oauthFieldsComplete ? (
              <Button size="lg" className="w-full" disabled>
                Continue with {provider.name}
              </Button>
            ) : (
              <Button asChild size="lg" className="w-full">
                <a href={oauthHref({ providerKey: provider.key, kind: mcpKind, name, environmentId, region, fields, returnTo })}>
                  Continue with {provider.name}
                </a>
              </Button>
            )}
            <p className="text-muted-foreground text-center text-xs">
              {nativeConnect
                ? `You choose what Firefight can reach on ${provider.name}'s install screen. No keys to copy.`
                : `You approve access on ${provider.name}'s consent screen. No keys to copy.`}
            </p>
          </div>

          {provider.app && !useMcpServer && (
            <div className="border-border flex flex-col gap-2 rounded-lg border p-3">
              <p className="text-sm font-medium">{provider.app.label}</p>
              <p className="text-muted-foreground text-xs">
                Connects Firefight&apos;s own {provider.name} app, which keeps incident actions and follow-ups in step with
                issues and sets up the webhook that sends changes back, so there is nothing to paste. Choose it under
                Settings, Workspace once it is connected.
              </p>
              <Button asChild size="sm" variant="outline" className="self-start">
                <a href={oauthHref({ providerKey: provider.key, kind: INTEGRATION_KINDS.NATIVE, name: separateAccount ? name : `${provider.name} issue sync`, environmentId, region: "", fields: {}, returnTo })}>
                  Connect the {provider.name} app
                </a>
              </Button>
            </div>
          )}

          {(showSecondAccountLink || showTokenLink) && (
            <div className="border-border text-muted-foreground flex items-center justify-center gap-3 border-t pt-3 text-xs">
              {showSecondAccountLink && (
                <button
                  type="button"
                  onClick={toggleSeparateAccount}
                  className="hover:text-foreground"
                >
                  Add a second account
                </button>
              )}
              {showSecondAccountLink && showTokenLink && (
                <span aria-hidden className="bg-border h-3 w-px" />
              )}
              {showTokenLink && (
                <button
                  type="button"
                  onClick={() => setUseToken(true)}
                  className="hover:text-foreground"
                >
                  Use a token instead
                </button>
              )}
            </div>
          )}
        </div>
      )}

      {showManualForm && (
        <div className="flex flex-col gap-4 pt-1">
          {(oauthAvailable || connectsWithUrl) && (
            <button
              type="button"
              onClick={() => setUseToken(false)}
              className="text-muted-foreground hover:text-foreground -mt-1 flex items-center gap-1 self-start text-xs"
            >
              <IconArrowLeft className="size-3.5" />
              {connectsWithUrl ? "Back to connection URL" : "Back to one-click connect"}
            </button>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-name">Connection name</Label>
            <Input
              id="connect-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder={
                provider.key === CUSTOM_MCP_PROVIDER_KEY
                  ? "e.g. Internal tools"
                  : provider.name
              }
            />
          </div>
          {regional && (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="connect-region">Region</Label>
              <RegionSelect id="connect-region" value={region} regions={provider.regions} onChange={chooseRegion} />
            </div>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-url">MCP server URL</Label>
            <Input
              id="connect-url"
              value={serverUrl}
              onChange={(event) => setServerUrl(event.target.value)}
              placeholder="https://example.com/mcp"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="connect-auth">Authorization header</Label>
            <Input
              id="connect-auth"
              type="password"
              value={authorization}
              onChange={(event) => setAuthorization(event.target.value)}
              placeholder="Bearer …  (optional, use a read-only key)"
            />
            <p className="text-muted-foreground text-xs">
              Stored encrypted and scoped to this connection. Never shared with
              agents or shown again.
            </p>
          </div>
          {environments.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <Label>Environment these credentials reach</Label>
              <EnvironmentSelect
                value={environmentId}
                environments={environments}
                onChange={setEnvironmentId}
              />
            </div>
          )}
          <ConnectFields fields={tokenFields} values={fields} onChange={setField} />
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={onDismiss}>
              Cancel
            </Button>
            <Button
              onClick={submit}
              disabled={submitting || !name || !serverUrl || !tokenFieldsComplete}
            >
              Connect &amp; discover tools
            </Button>
          </div>
        </div>
      )}
    </>
  );
}
