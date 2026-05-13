import { Head, usePage } from "@inertiajs/react";
import { IconCheck } from "@tabler/icons-react";

import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { installSlackAppPath } from "@/lib/routes";
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

type Scope = {
  name: string;
  explanation: string;
  boundary?: string;
};

type PermissionGroup = {
  title: string;
  description: string;
  scopes: Scope[];
};

const PERMISSION_GROUPS: PermissionGroup[] = [
  {
    title: "Sign-in and workspace identity",
    description:
      "Used to confirm who is signing in and which Slack workspace they belong to.",
    scopes: [
      {
        name: "openid",
        explanation:
          "Lets Slack verify the user's identity so Firefight can sign them in securely.",
      },
      {
        name: "profile",
        explanation:
          "Provides the user's name and avatar so Firefight can show who is using the workspace.",
      },
      {
        name: "email",
        explanation:
          "Provides the user's email address for account linking and membership checks.",
      },
      {
        name: "users:read",
        explanation:
          "Lets Firefight look up Slack users when matching members, resolving mentions, and showing responder details.",
      },
      {
        name: "users:read.email",
        explanation:
          "Lets Firefight match Slack identities to Firefight accounts by email during sign-in and onboarding.",
        boundary: "Used only for account linking, not for marketing.",
      },
      {
        name: "team:read",
        explanation:
          "Lets Firefight identify the Slack workspace being connected so the install is tied to the correct team.",
      },
    ],
  },
  {
    title: "Incident channels and notifications",
    description:
      "Used to create response spaces, post updates, and help responders coordinate in Slack.",
    scopes: [
      {
        name: "commands",
        explanation:
          "Enables the /firefight and /ff slash commands used to open Firefight workflows from Slack.",
      },
      {
        name: "chat:write",
        explanation:
          "Lets Firefight post incident announcements, status updates, and workflow messages in Slack.",
      },
      {
        name: "chat:write.public",
        explanation:
          "Lets Firefight post to public channels when sharing incident information without requiring the bot to already be in that channel.",
      },
      {
        name: "im:write",
        explanation:
          "Lets Firefight send direct messages for handoffs, sharing, and responder notifications.",
      },
      {
        name: "channels:manage",
        explanation:
          "Lets Firefight create and manage public incident channels during incident setup.",
        boundary: "Only for public incident channels Firefight creates.",
      },
      {
        name: "channels:join",
        explanation:
          "Lets the bot join the public channels it creates so it can post updates and respond to commands there.",
      },
      {
        name: "channels:read",
        explanation:
          "Lets Firefight look up public channel information when checking for incident channels and existing setup.",
      },
      {
        name: "groups:write",
        explanation:
          "Lets Firefight create and manage private incident channels when a workspace wants private response spaces.",
        boundary: "Only for private incident channels Firefight creates.",
      },
      {
        name: "app_mentions:read",
        explanation:
          "Lets Firefight respond when someone mentions the app in Slack during incident response.",
      },
    ],
  },
  {
    title: "Incident timeline and context",
    description:
      "Used to assemble timelines, capture important activity, and include relevant shared material in incident records.",
    scopes: [
      {
        name: "channels:history",
        explanation:
          "Lets Firefight read message history to build timelines and capture key updates.",
        boundary: "Only in public incident channels Firefight is invited to.",
      },
      {
        name: "groups:history",
        explanation:
          "Lets Firefight read message history for the same timeline and update workflows.",
        boundary: "Only in private incident channels Firefight is invited to.",
      },
      {
        name: "files:read",
        explanation:
          "Lets Firefight access files shared in incident conversations when those files need to be referenced or archived with incident context.",
      },
    ],
  },
  {
    title: "Lightweight workflow actions",
    description:
      "Used for smaller Slack interactions that help teams coordinate without leaving the channel.",
    scopes: [
      {
        name: "pins:write",
        explanation:
          "Lets Firefight pin important incident messages so responders can quickly find the current source of truth.",
      },
      {
        name: "pins:read",
        explanation:
          "Lets Firefight track pin changes so pinned messages stay reflected in the incident timeline.",
      },
      {
        name: "reactions:read",
        explanation:
          "Lets Firefight react to emoji-based workflows, such as turning a reaction into an action item or follow-up.",
      },
      {
        name: "reactions:write",
        explanation:
          "Lets Firefight add reactions when acknowledging or updating workflow state in Slack.",
      },
    ],
  },
];

const TOTAL_SCOPES = PERMISSION_GROUPS.reduce(
  (sum, group) => sum + group.scopes.length,
  0,
);

export default function Install() {
  const { teamName } = usePage<InstallPageProps>().props;

  return (
    <div className="dark">
      <Head title="Install Firefight" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(115,211,238,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(115,211,238,0.03)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[460px]">
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

              <ul className="mb-8 space-y-3 text-left">
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
          </div>
        </main>
      </div>
    </div>
  );
}

function PermissionsDialog() {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <button
          type="button"
          className="mt-5 inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-card"
        >
          See all {TOTAL_SCOPES} permissions
          <span aria-hidden="true" className="translate-y-[-0.5px]">
            →
          </span>
        </button>
      </DialogTrigger>

      <DialogContent
        style={{
          maxWidth: "560px",
          maxHeight: "min(85vh, 720px)",
          display: "grid",
          gridTemplateRows: "auto minmax(0, 1fr)",
        }}
        className="dark w-[calc(100vw-2rem)] gap-0 overflow-hidden border-border/70 bg-card p-0 shadow-[0_24px_60px_-24px_rgba(10,30,46,0.22),0_8px_20px_-8px_rgba(10,30,46,0.08)] [&>button]:text-muted-foreground [&>button]:hover:text-foreground"
      >
        <DialogHeader className="space-y-1.5 border-b border-border/60 px-6 pt-6 pb-5 sm:text-left">
          <DialogTitle>Permissions Firefight needs</DialogTitle>
          <DialogDescription className="leading-relaxed">
            Slack groups these OAuth scopes by what they let Firefight do in
            your workspace.
          </DialogDescription>
        </DialogHeader>

        <div className="overflow-y-auto overscroll-contain">
          <div className="px-6 pt-7 pb-7">
            {PERMISSION_GROUPS.map((group) => (
              <section
                key={group.title}
                className="border-t border-border/50 pt-8 first:border-t-0 first:pt-0"
              >
                <div className="mb-5">
                  <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground/65 tabular-nums">
                    {group.scopes.length} scope
                    {group.scopes.length === 1 ? "" : "s"}
                  </p>
                  <h3 className="mt-2 text-sm font-semibold text-foreground">
                    {group.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                    {group.description}
                  </p>
                </div>

                <dl className="space-y-5 pb-2">
                  {group.scopes.map((scope) => (
                    <div key={scope.name} className="space-y-[7px]">
                      <dt>
                        <code className="inline-block rounded-[4px] bg-foreground/[0.05] px-[7px] py-[3px] font-mono text-xs font-semibold leading-none text-foreground">
                          {scope.name}
                        </code>
                      </dt>
                      <dd className="text-sm leading-relaxed text-foreground/85">
                        {scope.explanation}
                        {scope.boundary ? (
                          <>
                            {" "}
                            <span className="italic text-foreground/55">
                              {scope.boundary}
                            </span>
                          </>
                        ) : null}
                      </dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function SlackLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 122.8 122.8"
      className={className}
      aria-hidden="true"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M25.8 77.6a12.9 12.9 0 1 1-12.9-12.9h12.9zm6.5 0a12.9 12.9 0 0 1 25.8 0v32.3a12.9 12.9 0 0 1-25.8 0z" fill="#E01E5A" />
      <path d="M45.2 25.8a12.9 12.9 0 1 1 12.9-12.9v12.9zm0 6.5a12.9 12.9 0 0 1 0 25.8H12.9a12.9 12.9 0 0 1 0-25.8z" fill="#36C5F0" />
      <path d="M97 45.2a12.9 12.9 0 1 1 12.9 12.9H97zm-6.5 0a12.9 12.9 0 0 1-25.8 0V12.9a12.9 12.9 0 0 1 25.8 0z" fill="#2EB67D" />
      <path d="M77.6 97a12.9 12.9 0 1 1-12.9 12.9V97zm0-6.5a12.9 12.9 0 0 1 0-25.8h32.3a12.9 12.9 0 0 1 0 25.8z" fill="#ECB22E" />
    </svg>
  );
}


