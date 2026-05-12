import { Head, usePage } from "@inertiajs/react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

interface InstallPageProps {
  [key: string]: unknown;
  teamName: string;
  teamId: string;
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
            <div className="relative rounded-[14px] border border-[rgba(115,211,238,0.3)] bg-card px-8 py-10 shadow-[0_1px_2px_0_rgba(0,0,0,0.2),0_20px_60px_0_rgba(0,0,0,0.4),0_0px_60px_0_rgba(115,211,238,0.06)] sm:px-10 sm:py-12">
              <div className="mb-8 flex flex-col items-center space-y-4 text-center">
                <svg width="36" height="36" viewBox="20 20 34 39" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                  <path d="M50.8096 30.2171C52.7322 32.9637 53.8622 36.3063 53.8623 39.9134L53.8564 40.3509C53.6246 49.4995 46.1351 56.8448 36.9307 56.845L36.4941 56.8392C35.8569 56.823 35.2282 56.7705 34.6104 56.6858L36.0596 54.3177C36.3476 54.3348 36.6383 54.345 36.9307 54.345C44.9005 54.3448 51.3623 47.8833 51.3623 39.9134C51.3622 37.2371 50.632 34.7317 49.3623 32.5833L50.8096 30.2171ZM36.9307 22.9827C38.8085 22.9828 40.6147 23.2894 42.3027 23.8538L40.7695 26.0003C39.5471 25.6637 38.26 25.4827 36.9307 25.4827C28.961 25.4829 22.5003 31.9437 22.5 39.9134C22.5 42.9326 23.4275 45.735 25.0127 48.052L23.4805 50.1966C21.2976 47.3457 20 43.7813 20 39.9134C20.0003 30.563 27.5803 22.9829 36.9307 22.9827Z" fill="#73D3EE"/>
                  <path d="M23.336 59L51.2016 20L27.6572 58.4694L23.336 59Z" fill="#73D3EE"/>
                </svg>
                <div className="space-y-2">
                <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                  Install Firefight
                </h1>
                <p className="text-[0.9375rem] leading-relaxed text-muted-foreground">
                  Connect Firefight to{" "}
                  <span className="font-medium text-foreground">
                    {teamName}
                  </span>
                  . The bot needs the following permissions:
                </p>
                </div>
              </div>

              <ul className="mb-8 space-y-3 text-left">
                {PERMISSIONS.map((permission) => (
                  <li
                    key={permission}
                    className="flex items-start gap-3 text-sm text-foreground"
                  >
                    <Checkmark className="mt-[3px] size-4 shrink-0 text-primary" />
                    <span>{permission}</span>
                  </li>
                ))}
              </ul>

              <a
                href="/auth/slack"
                className="flex h-11 w-full items-center justify-center rounded-md bg-foreground text-sm font-medium text-background shadow-sm transition-colors hover:bg-foreground/90"
              >
                Add Firefight to Slack
              </a>

              <PermissionsDialog />

              <p className="mt-5 text-center text-xs leading-relaxed text-muted-foreground">
                You'll need to be a Slack workspace admin to complete the
                install.
              </p>
            </div>
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
          className="mt-5 inline-flex w-full items-center justify-center gap-1.5 rounded text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-card"
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
        className="w-[calc(100vw-2rem)] gap-0 overflow-hidden border-border/70 bg-card p-0 shadow-[0_24px_60px_-24px_rgba(10,30,46,0.22),0_8px_20px_-8px_rgba(10,30,46,0.08)]"
      >
        <DialogHeader className="space-y-1.5 border-b border-border/60 px-6 pt-6 pb-5 sm:text-left">
          <DialogTitle className="text-[1.0625rem] font-medium tracking-[-0.01em] text-foreground">
            Permissions Firefight needs
          </DialogTitle>
          <DialogDescription className="text-[13px] leading-relaxed text-muted-foreground">
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
                  <p className="text-[9.5px] font-semibold uppercase tracking-[0.12em] text-muted-foreground/65 tabular-nums">
                    {group.scopes.length} scope
                    {group.scopes.length === 1 ? "" : "s"}
                  </p>
                  <h3 className="mt-2 text-[15px] font-semibold tracking-[-0.015em] text-foreground">
                    {group.title}
                  </h3>
                  <p className="mt-2 text-[13px] leading-[1.6] text-muted-foreground">
                    {group.description}
                  </p>
                </div>

                <dl className="space-y-5 pb-2">
                  {group.scopes.map((scope) => (
                    <div key={scope.name} className="space-y-[7px]">
                      <dt>
                        <code className="inline-block rounded-[4px] bg-foreground/[0.05] px-[7px] py-[3px] font-mono text-[11.5px] font-semibold leading-none tracking-[-0.01em] text-foreground">
                          {scope.name}
                        </code>
                      </dt>
                      <dd className="text-[13px] leading-[1.55] text-foreground/85">
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

function Checkmark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <path d="M3 8l3.5 3.5L13 5" />
    </svg>
  );
}
