import { Head, usePage } from "@inertiajs/react";

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

const PERMISSION_GROUPS = [
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
          "Provides the user's email address for account linking, invitations, and membership checks.",
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
          "Lets Firefight read message history in public incident channels so it can build timelines and capture key updates.",
      },
      {
        name: "groups:history",
        explanation:
          "Lets Firefight read message history in private incident channels for the same timeline and update workflows.",
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

export default function Install() {
  const { teamName } = usePage<InstallPageProps>().props;

  return (
    <>
      <Head title="Install Firefight" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(10,30,46,0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(10,30,46,0.035)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[460px]">
            <div className="relative rounded-xl border border-border bg-card px-8 py-10 shadow-[0_1px_0_0_rgba(10,30,46,0.02),0_1px_2px_0_rgba(10,30,46,0.04),0_8px_24px_-8px_rgba(10,30,46,0.08)] sm:px-10 sm:py-12">
              <div className="mb-8 space-y-2 text-center">
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

              <p className="mt-6 text-center text-xs leading-relaxed text-muted-foreground">
                You'll need to be a Slack workspace admin to complete the
                install.
              </p>

              <details className="mt-6 rounded-lg border border-border bg-background/70 p-4 text-left">
                <summary className="cursor-pointer list-none text-sm font-medium text-foreground marker:hidden">
                  <span className="inline-flex items-center gap-2">
                    <Chevron className="size-4 text-muted-foreground" />
                    Why these permissions are needed
                  </span>
                </summary>

                <div className="mt-4 space-y-5">
                  <p className="text-xs leading-relaxed text-muted-foreground">
                    Firefight requests Slack permissions so it can create and run
                    incident workflows inside your workspace. Below is each
                    scope we request and how it is used.
                  </p>

                  {PERMISSION_GROUPS.map((group) => (
                    <section key={group.title} className="space-y-3">
                      <div className="space-y-1">
                        <h2 className="text-sm font-medium text-foreground">
                          {group.title}
                        </h2>
                        <p className="text-xs leading-relaxed text-muted-foreground">
                          {group.description}
                        </p>
                      </div>

                      <ul className="space-y-2">
                        {group.scopes.map((scope) => (
                          <li
                            key={scope.name}
                            className="rounded-md border border-border/80 bg-card px-3 py-2"
                          >
                            <div className="text-xs font-medium text-foreground">
                              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-[0.75rem]">
                                {scope.name}
                              </code>
                            </div>
                            <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                              {scope.explanation}
                            </p>
                          </li>
                        ))}
                      </ul>
                    </section>
                  ))}
                </div>
              </details>
            </div>
          </div>
        </main>
      </div>
    </>
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

function Chevron({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <path d="M3.5 6 8 10.5 12.5 6" />
    </svg>
  );
}
