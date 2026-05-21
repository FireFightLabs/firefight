import { usePage } from "@inertiajs/react";
import { IconCheck } from "@tabler/icons-react";

import { Card } from "@/components/card";
import { installSlackAppPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { PermissionsDialog } from "@/pages/onboarding/components/install/permissions-dialog";
import { SlackButton } from "@/components/auth/slack-button";
import type { SharedProps } from "@/types";

interface InstallPageProps extends SharedProps {
  [key: string]: unknown;
  teamName: string;
}

const PERMISSIONS = [
  "Create and manage incident channels",
  "Post incident updates and announcements",
  "Add slash commands (/firefight, /ff)",
  "Read channel history for incident timelines",
  "Add emoji reactions and pin key messages",
];

export default function Install() {
  const { teamName } = usePage<InstallPageProps>().props;

  return (
    <AuthLayout title="Install Firefight" containerClassName="max-w-[460px]">
      <Card variant="glow">
        <CardHeader
          title="Install Firefight"
          subtitle={
            <>
              Connect Firefight to{" "}
              <span className="font-medium text-foreground">{teamName}</span>.
              <br />
              The bot needs the following permissions:
            </>
          }
        />

        <ul className="mx-auto mb-8 w-fit space-y-3 text-left">
          {PERMISSIONS.map((permission) => (
            <li
              key={permission}
              className="flex items-start gap-3 text-sm text-foreground"
            >
              <IconCheck className="mt-[3px] size-4 shrink-0 text-primary" stroke={2.5} />
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
      </Card>
    </AuthLayout>
  );
}
