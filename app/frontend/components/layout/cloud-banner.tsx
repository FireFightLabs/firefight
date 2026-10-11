import { usePage } from "@inertiajs/react";
import { IconClock, IconCreditCard } from "@tabler/icons-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import type { CloudBanner as CloudBannerProps } from "@/types";

// A note that needs nothing done, such as the days left in a trial, sits in one quiet line.
function QuietBanner({ banner }: { banner: CloudBannerProps }) {
  return (
    <div className="mx-6 mt-6 flex flex-col items-start gap-2 rounded-lg border border-border bg-surface-card px-4 py-2.5 text-sm sm:flex-row sm:items-center sm:justify-between">
      <p className="flex items-start gap-2.5 text-fg-body">
        <IconClock className="mt-0.5 size-4 shrink-0 text-fg-secondary" />
        <span>
          <span className="font-medium text-fg-primary">{banner.title}</span> {banner.detail}
        </span>
      </p>
      {banner.action ? (
        <Button asChild variant="ghost" size="sm" className="shrink-0">
          <a href={banner.action.href}>{banner.action.label}</a>
        </Button>
      ) : null}
    </div>
  );
}

// Set by the cloud engine while there is something to say about billing, absent on an install someone runs themselves.
export function CloudBanner() {
  const { cloudBanner } = usePage().props;

  if (!cloudBanner) {
    return null;
  }

  if (cloudBanner.tone === "quiet") {
    return <QuietBanner banner={cloudBanner} />;
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
