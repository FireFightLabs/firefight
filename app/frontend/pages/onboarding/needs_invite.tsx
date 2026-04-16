import { Head, usePage } from "@inertiajs/react";

interface NeedsInvitePageProps {
  [key: string]: unknown;
  teamName?: string;
}

export default function NeedsInvite() {
  const { teamName } = usePage<NeedsInvitePageProps>().props;

  return (
    <>
      <Head title="Invitation required" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(10,30,46,0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(10,30,46,0.035)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[420px]">
            <div className="relative rounded-xl border border-border bg-card px-8 py-10 text-center shadow-[0_1px_0_0_rgba(10,30,46,0.02),0_1px_2px_0_rgba(10,30,46,0.04),0_8px_24px_-8px_rgba(10,30,46,0.08)] sm:px-10 sm:py-12">
              <div className="mb-8 space-y-2">
                <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                  Invitation required
                </h1>
                <p className="mx-auto max-w-[34ch] text-[0.9375rem] leading-relaxed text-muted-foreground">
                  {teamName ? (
                    <>
                      Firefight is set up for{" "}
                      <span className="font-medium text-foreground">
                        {teamName}
                      </span>
                      , but you're not a member yet.
                    </>
                  ) : (
                    <>
                      Firefight is set up for your workspace, but you're not a
                      member yet.
                    </>
                  )}
                </p>
              </div>

              <p className="mx-auto mb-8 max-w-[34ch] text-sm leading-relaxed text-muted-foreground">
                Ask a workspace admin to send you an invite, or run a command
                like <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-[0.8125rem] text-foreground">/firefight</code>{" "}
                in Slack to provision yourself automatically.
              </p>

              <a
                href="/login"
                className="inline-flex h-9 items-center justify-center rounded-md border border-border bg-card px-4 text-sm font-medium text-foreground shadow-sm transition-colors hover:bg-accent"
              >
                Back to sign in
              </a>
            </div>
          </div>
        </main>
      </div>
    </>
  );
}
