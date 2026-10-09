import { usePage } from "@inertiajs/react";
import { IconCreditCard } from "@tabler/icons-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

// Set by the cloud engine while a billing problem needs attention, absent on an install someone runs themselves.
export function CloudBanner() {
  const { cloudBanner } = usePage().props;

  if (!cloudBanner) {
    return null;
  }

  return (
    <Alert
      variant="destructive"
      className="mx-6 mt-6 w-auto flex flex-col items-start justify-between gap-3 border-border edge-bar [--edge-bar:var(--error)] bg-error-tint text-fg-primary sm:flex-row sm:items-center *:data-[slot=alert-description]:text-fg-body"
    >
      <div className="flex items-start gap-3">
        <IconCreditCard className="mt-0.5 size-5 shrink-0 text-error" />
        <div>
          <AlertTitle>{cloudBanner.title}</AlertTitle>
          <AlertDescription>{cloudBanner.detail}</AlertDescription>
        </div>
      </div>
      {cloudBanner.action ? (
        <Button asChild variant="outline" size="sm" className="shrink-0">
          <a href={cloudBanner.action.href}>{cloudBanner.action.label}</a>
        </Button>
      ) : null}
    </Alert>
  );
}
