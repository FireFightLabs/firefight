import { useState } from "react";
import { router } from "@inertiajs/react";

import type { EnvironmentOption, IntegrationProvider } from "@/types/serializers";
import { integrationsPath } from "@/lib/routes";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
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
  // For a team that already runs an MCP server for the database, or cannot open it to the internet.
  onUseMcpServer: () => void;
}

type FieldErrors = Partial<Record<"name" | "connection", string>>;

type Certificates = {
  root_cert: string;
  client_cert: string;
  client_key: string;
};

const NO_CERTIFICATES: Certificates = { root_cert: "", client_cert: "", client_key: "" };

const CERTIFICATE_FIELDS: { key: keyof Certificates; label: string; hint: string; placeholder: string }[] = [
  {
    key: "root_cert",
    label: "CA certificate",
    hint: "For a database whose certificate is signed by its own authority, such as a cloud provider's.",
    placeholder: "-----BEGIN CERTIFICATE-----",
  },
  {
    key: "client_cert",
    label: "Client certificate",
    hint: "For a database that asks the client to prove who it is.",
    placeholder: "-----BEGIN CERTIFICATE-----",
  },
  {
    key: "client_key",
    label: "Client key",
    hint: "The unencrypted private key for the client certificate.",
    placeholder: "-----BEGIN PRIVATE KEY-----",
  },
];

// A database connected from a URL, one per environment. The same name adds an environment to the connection, or
// replaces the URL of one it has. The server checks the URL before saving anything and says what is wrong on the form.
export function ConnectionUrlForm({ provider, environments, returnTo, onDismiss, onUseMcpServer }: ConnectionUrlFormProps) {
  const [name, setName] = useState(provider.name);
  const [connectionUrl, setConnectionUrl] = useState("");
  const [environmentId, setEnvironmentId] = useState(ALL_ENVIRONMENTS);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [showCertificates, setShowCertificates] = useState(false);
  const [certificates, setCertificates] = useState<Certificates>(NO_CERTIFICATES);

  function revealCertificates() {
    setShowCertificates(true);
  }

  function setCertificate(key: keyof Certificates, value: string) {
    setCertificates((current) => ({ ...current, [key]: value }));
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
        connection_url: connectionUrl,
        certificates,
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
        <p className="text-muted-foreground text-xs">
          Use a database user that can only read. Firefight also runs every query read-only and stops any that
          runs longer than 10 seconds. Connections over the internet are always encrypted. Stored encrypted, never
          shown again.
        </p>
      </div>
      {showCertificates ? (
        CERTIFICATE_FIELDS.map((field) => (
          <div key={field.key} className="flex flex-col gap-1.5">
            <Label htmlFor={`connect-${field.key}`}>
              {field.label} <span className="text-muted-foreground font-normal">(optional)</span>
            </Label>
            <Textarea
              id={`connect-${field.key}`}
              rows={3}
              spellCheck={false}
              value={certificates[field.key]}
              onChange={(event) => setCertificate(field.key, event.target.value)}
              placeholder={field.placeholder}
              className="font-mono text-xs"
            />
            <p className="text-muted-foreground text-xs">{field.hint}</p>
          </div>
        ))
      ) : (
        <button type="button" onClick={revealCertificates} className="text-muted-foreground hover:text-foreground self-start text-xs">
          Add certificates
        </button>
      )}
      {errors.connection && <p className="text-destructive text-sm">{errors.connection}</p>}
      <div className="flex items-center justify-end gap-2 pt-2">
        <button type="button" onClick={onUseMcpServer} className="text-muted-foreground hover:text-foreground mr-auto text-xs">
          Use an MCP server instead
        </button>
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
