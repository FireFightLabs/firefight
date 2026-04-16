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
