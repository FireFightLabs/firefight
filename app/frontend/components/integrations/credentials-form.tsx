import { useState } from "react";
import { router } from "@inertiajs/react";

import type { EnvironmentOption, IntegrationProvider } from "@/types/serializers";
import { integrationsPath } from "@/lib/routes";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  ALL_ENVIRONMENTS,
  EnvironmentSelect,
  toEnvironmentId,
} from "@/components/integrations/environment-select";

interface CredentialsFormProps {
  provider: IntegrationProvider;
  environments: EnvironmentOption[];
  returnTo?: string;
  onDismiss: () => void;
}

type FieldErrors = Partial<Record<"name" | "connection", string>>;

// A provider connected with an API token and whatever else it asks for, one set per environment. The fields come from
// the provider's pack. The same name adds an environment or replaces its values. The server checks them with the
// provider before saving anything and says what is wrong on the form.
export function CredentialsForm({ provider, environments, returnTo, onDismiss }: CredentialsFormProps) {
  const [name, setName] = useState(provider.name);
  const [values, setValues] = useState<Record<string, string>>({});
  const [environmentId, setEnvironmentId] = useState(ALL_ENVIRONMENTS);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<FieldErrors>({});
  const complete = provider.credentialFields.every((field) => (values[field.key] ?? "").trim() !== "");

  function setValue(key: string, value: string) {
    setValues((current) => ({ ...current, [key]: value }));
  }

  function finish() {
    setSubmitting(false);
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    router.post(
      integrationsPath(),
      {
        provider: provider.key,
        name,
        credentials: values,
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
      {provider.credentialFields.map((field) => (
        <div key={field.key} className="flex flex-col gap-1.5">
          <Label htmlFor={`connect-${field.key}`}>{field.label}</Label>
          <Input
            id={`connect-${field.key}`}
            type={field.secret ? "password" : "text"}
            autoComplete="off"
            spellCheck={false}
            value={values[field.key] ?? ""}
            onChange={(event) => setValue(field.key, event.target.value)}
            placeholder={field.placeholder}
          />
          <p className="text-muted-foreground text-xs">
            {field.hint}
            {field.secret && " Stored encrypted, never shown again."}
          </p>
        </div>
      ))}
      {errors.connection && <p className="text-destructive text-sm">{errors.connection}</p>}
      <div className="flex items-center justify-end gap-2 pt-2">
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
