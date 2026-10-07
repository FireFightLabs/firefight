import { Link, usePage } from "@inertiajs/react";
import { IconCheck } from "@tabler/icons-react";

import { installSlackAppPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { PermissionsDialog } from "@/pages/onboarding/components/install/permissions-dialog";
import { SlackButton } from "@/components/auth/slack-button";
import type { SharedProps } from "@/types";

interface InstallPageProps extends SharedProps {
  [key: string]: unknown;
  teamName: string;
  // Set when connecting a workspace that already exists, which can carry on without Slack for now.
  skipPath: string | null;
}

const PERMISSIONS = [
  "Create and manage incident channels",
  "Post incident updates and announcements",
  "Add slash commands (/firefight, /ff)",
  "Read channel history for incident timelines",
  "Add emoji reactions and pin key messages",
];

export default function Install() {
  const { teamName, skipPath } = usePage<InstallPageProps>().props;

  return (
    <AuthLayout title="Install Firefight" containerClassName="max-w-[460px]">
      <div>
        <CardHeader
          title="Install Firefight"
          subtitle={
            <>
              Connect Firefight to{" "}
              <span className="font-medium text-fg-primary">{teamName}</span>.
              <br />
              The bot needs the following permissions:
            </>
          }
        />

        <ul className="mx-auto mb-8 w-fit space-y-3 text-left">
          {PERMISSIONS.map((permission) => (
            <li
              key={permission}
              className="flex items-start gap-3 text-sm text-fg-primary"
            >
              <IconCheck className="mt-[3px] size-4 shrink-0 text-brand" stroke={2.5} />
              <span>{permission}</span>
            </li>
          ))}
        </ul>

        <SlackButton
          href={installSlackAppPath()}
          label="Add Firefight to Slack"
        />

        <PermissionsDialog />

        <p className="mt-5 text-center text-xs leading-relaxed text-muted-foreground">
          You'll need to be a Slack workspace admin to complete the install.
        </p>

        {skipPath ? (
          <p className="mt-3 text-center text-xs">
            <Link
              href={skipPath}
              className="text-muted-foreground underline decoration-border underline-offset-[3px] transition-colors hover:text-fg-primary hover:decoration-foreground"
            >
              Not now
            </Link>
          </p>
        ) : null}
      </div>
    </AuthLayout>
  );
}
