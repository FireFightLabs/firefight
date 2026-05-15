import { usePage } from "@inertiajs/react";
import { IconCheck } from "@tabler/icons-react";

import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { installSlackAppPath } from "@/lib/routes";
import { AuthLayout } from "@/modules/auth/components/auth-layout";
import { PermissionsDialog } from "@/modules/auth/components/permissions-dialog";
import { SlackLogo } from "@/modules/auth/components/slack-logo";
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
        <div className="mb-8 flex flex-col items-center space-y-4 text-center">
          <FireFightLogo />
          <div className="space-y-2">
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">
              Install Firefight
            </h1>
            <p className="text-sm leading-relaxed text-muted-foreground">
              Connect Firefight to{" "}
              <span className="font-medium text-foreground">
                {teamName}
              </span>
              .<br />The bot needs the following permissions:
            </p>
          </div>
        </div>

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

        <Button
          asChild
          variant="outline"
          className="h-11 w-full cursor-pointer justify-center gap-3 border-primary/45 bg-card font-medium shadow-[0_0_16px_rgba(115,211,238,0.15),0_0_4px_rgba(115,211,238,0.3)] transition-[box-shadow,transform] hover:bg-card hover:shadow-[0_0_24px_rgba(115,211,238,0.4),0_0_8px_rgba(115,211,238,0.55)] active:translate-y-px"
        >
          <a href={installSlackAppPath()}>
            <SlackLogo className="size-[18px] shrink-0" />
            <span className="text-[0.9375rem]">Add Firefight to Slack</span>
          </a>
        </Button>

        <PermissionsDialog />

        <p className="mt-5 text-center text-xs leading-relaxed text-muted-foreground">
          You'll need to be a Slack workspace admin to complete the
          install.
        </p>
      </Card>
    </AuthLayout>
  );
}

