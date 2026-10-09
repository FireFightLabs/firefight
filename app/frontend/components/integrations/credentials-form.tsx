import { useState, type FormEvent } from "react";
import { router } from "@inertiajs/react";

import type { EnvironmentOption, IntegrationProvider } from "@/types/serializers";
import { integrationsPath, listScopesIntegrationsPath } from "@/lib/routes";
import { postJson } from "@/lib/http";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  ALL_ENVIRONMENTS,
  EnvironmentSelect,
  toEnvironmentId,
} from "@/components/integrations/environment-select";
import { defaultRegion, RegionSelect } from "@/components/integrations/region-select";
import {
  ConnectFields,
  connectFieldsComplete,
  type ConnectValue,
  type ConnectValues,
  type ScopeLister,
} from "@/components/integrations/connect-fields";
import type { ScopeListing } from "@/components/integrations/scope-select";

interface CredentialsFormProps {
  provider: IntegrationProvider;
  environments: EnvironmentOption[];
  returnTo?: string;
  onDismiss: () => void;
  // For a provider that also runs an MCP server of its own, reached instead of the credentials.
  onUseMcpServer?: () => void;
}

type FieldErrors = Partial<Record<"name" | "connection", string>>;

// A provider connected with an API token and whatever else it asks for, one set per environment. The fields come from
// the provider's pack. The same name adds an environment or replaces its values. The server checks them with the
// provider before saving anything and says what is wrong on the form.
export function CredentialsForm({ provider, environments, returnTo, onDismiss, onUseMcpServer }: CredentialsFormProps) {
  const [name, setName] = useState(provider.name);
  const [values, setValues] = useState<Record<string, string>>({});
  const [environmentId, setEnvironmentId] = useState(ALL_ENVIRONMENTS);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [region, setRegion] = useState(defaultRegion(provider));
  const [fields, setFields] = useState<ConnectValues>({});
  // A pack has no server address, so every connect field it lists belongs to the environment.
  const connectFields = provider.connectFields.filter((field) => !field.address);
  const complete =
    provider.credentialFields.every((field) => field.optional || (values[field.key] ?? "").trim() !== "") &&
    connectFieldsComplete(connectFields, fields);

  // What the typed credentials can read, listed by the provider before anything is saved, again once they change.
  const otherFields = Object.fromEntries(
    Object.entries(fields).filter(([key]) => !connectFields.some((field) => field.key === key && field.scope)),
  );
  const scopes: ScopeLister = {
    key: JSON.stringify([values, region, otherFields]),
    load: listScopes,
  };

  async function listScopes(): Promise<ScopeListing> {
    const answer = await postJson<ScopeListing>(listScopesIntegrationsPath(), {
      provider: provider.key,
      credentials: values,
      fields: otherFields,
      region,
    });
    return answer.data ?? { options: [], error: "Firefight could not list them." };
  }

  function setField(key: string, value: ConnectValue) {
    setFields((current) => ({ ...current, [key]: value }));
  }

  function setValue(key: string, value: string) {
    setValues((current) => ({ ...current, [key]: value }));
  }

  function finish() {
    setSubmitting(false);
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    router.post(
      integrationsPath(),
      {
        provider: provider.key,
        name,
        credentials: values,
        fields,
        region,
        environment_id: toEnvironmentId(environmentId),
        return_to: returnTo,
      },
      { onSuccess: onDismiss, onError: setErrors, onFinish: finish },
    );
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-4 pt-1">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="connect-name">Connection name</Label>
        <Input id="connect-name" value={name} onChange={(event) => setName(event.target.value)} />
        {errors.name && <p className="text-destructive text-xs">{errors.name}</p>}
      </div>
      {environments.length > 0 && (
        <div className="flex flex-col gap-1.5">
          <Label>Environment these credentials reach</Label>
          <EnvironmentSelect value={environmentId} environments={environments} onChange={setEnvironmentId} />
        </div>
      )}
      {provider.regions.length > 1 && (
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="connect-region">Region</Label>
          <RegionSelect id="connect-region" value={region} regions={provider.regions} onChange={setRegion} />
        </div>
      )}
      {provider.credentialFields.map((field) => (
        <div key={field.key} className="flex flex-col gap-1.5">
          <Label htmlFor={`connect-${field.key}`}>
            {field.label}
            {field.optional && <span className="text-muted-foreground font-normal"> (optional)</span>}
          </Label>
          {field.multiline ? (
            <Textarea
              id={`connect-${field.key}`}
              autoComplete="off"
              spellCheck={false}
              rows={5}
              className="font-mono text-xs"
              value={values[field.key] ?? ""}
              onChange={(event) => setValue(field.key, event.target.value)}
              placeholder={field.placeholder}
            />
          ) : (
            <Input
              id={`connect-${field.key}`}
              type={field.secret ? "password" : "text"}
              autoComplete="off"
              spellCheck={false}
              value={values[field.key] ?? ""}
              onChange={(event) => setValue(field.key, event.target.value)}
              placeholder={field.placeholder}
            />
          )}
          <p className="text-muted-foreground text-xs">
            {field.hint}
            {field.secret && " Stored encrypted, never shown again."}
          </p>
        </div>
      ))}
      <ConnectFields fields={connectFields} values={fields} scopes={scopes} onChange={setField} />
      {errors.connection && <p className="text-destructive text-sm">{errors.connection}</p>}
      <div className="flex items-center justify-end gap-2 pt-2">
        {onUseMcpServer && (
          <button type="button" onClick={onUseMcpServer} className="text-muted-foreground hover:text-foreground mr-auto text-xs">
            Use an MCP server instead
          </button>
        )}
        <Button type="button" variant="outline" onClick={onDismiss}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting || !name.trim() || !complete}>
          Connect
        </Button>
      </div>
    </form>
  );
}
