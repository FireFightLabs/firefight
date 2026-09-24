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

interface ConnectionUrlFormProps {
  provider: IntegrationProvider;
  environments: EnvironmentOption[];
  returnTo?: string;
  onDismiss: () => void;
}

type FieldErrors = Partial<Record<"name" | "connection_url", string>>;

// A database connected from a URL, one per environment. The same name adds an environment to the connection, or
// replaces the URL of one it has. The server checks the URL before saving anything and says what is wrong on the form.
export function ConnectionUrlForm({ provider, environments, returnTo, onDismiss }: ConnectionUrlFormProps) {
  const [name, setName] = useState(provider.name);
  const [connectionUrl, setConnectionUrl] = useState("");
  const [environmentId, setEnvironmentId] = useState(ALL_ENVIRONMENTS);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<FieldErrors>({});

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
        connection_url: connectionUrl,
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
          <Label>Environment this database is</Label>
          <EnvironmentSelect value={environmentId} environments={environments} onChange={setEnvironmentId} />
        </div>
      )}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="connect-connection-url">Connection URL</Label>
        <Input
          id="connect-connection-url"
          type="password"
          autoComplete="off"
          value={connectionUrl}
          onChange={(event) => setConnectionUrl(event.target.value)}
          placeholder="postgresql://readonly:password@db.example.com:5432/app"
        />
        {errors.connection_url ? (
          <p className="text-destructive text-xs">{errors.connection_url}</p>
        ) : (
          <p className="text-muted-foreground text-xs">
            Use a database user that can only read. Firefight also runs every query read-only and stops any that
            runs longer than 10 seconds. Stored encrypted, never shown again.
          </p>
        )}
      </div>
      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="outline" onClick={onDismiss}>
          Cancel
        </Button>
        <Button type="submit" disabled={submitting || !name.trim() || !connectionUrl.trim()}>
          Connect
        </Button>
      </div>
    </form>
  );
}
