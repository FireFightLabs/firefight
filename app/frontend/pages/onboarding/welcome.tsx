import { Head } from "@inertiajs/react";

interface WelcomePageProps {
  [key: string]: unknown;
  userName: string;
  workspaceName: string;
}

export default function Welcome({ userName, workspaceName }: WelcomePageProps) {
  return (
    <>
      <Head title="Welcome to Firefight" />

      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(10,30,46,0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(10,30,46,0.035)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[560px]">
            <div className="rounded-xl border border-border bg-card px-8 py-10 shadow-[0_1px_0_0_rgba(10,30,46,0.02),0_1px_2px_0_rgba(10,30,46,0.04),0_8px_24px_-8px_rgba(10,30,46,0.08)] sm:px-10 sm:py-12">
              <div className="mb-8 space-y-3">
                <div className="inline-flex items-center rounded-full border border-primary/20 bg-primary/10 px-3 py-1 text-[0.7rem] font-medium uppercase tracking-[0.18em] text-primary/90">
                  Welcome
                </div>

                <h1 className="text-[1.9rem] font-medium leading-[1.1] tracking-[-0.025em] text-foreground">
                  Firefight is ready in {workspaceName}
                </h1>

                <p className="max-w-[44ch] text-[0.95rem] leading-relaxed text-muted-foreground">
                  {userName}, thanks for giving it a try. I built Firefight because incident tooling too often feels bloated, opaque, and priced for large companies rather than working teams.
                </p>
              </div>

              <div className="space-y-4 text-sm leading-relaxed text-foreground">
                <p>
                  Firefight is meant to be straightforward: declare an incident, create the response space, keep the timeline clear, and make the workflow understandable.
                </p>

                <p>
                  It is not trying to automate every part of incident response or hide critical behavior behind layers of setup. If something feels rough, confusing, or missing, that is useful feedback for us right now.
                </p>

                <p className="text-muted-foreground">
                  We&apos;re building this in the open, and the goal is simple: software teams can trust during a bad day, not just software that demos well.
                </p>
              </div>

              <div className="mt-8 rounded-lg border border-border bg-background/70 px-4 py-4">
                <p className="text-xs font-medium uppercase tracking-[0.16em] text-primary/90">
                  What to do next
                </p>
                <ul className="mt-3 space-y-2 text-sm leading-relaxed text-muted-foreground">
                  <li>Open the dashboard and review your workspace setup.</li>
                  <li>Try creating your first incident from Slack.</li>
                  <li>Send feedback directly if anything feels off.</li>
                </ul>
              </div>

              <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="text-sm text-muted-foreground">
                  Uros Nikolic
                  <div className="text-xs">Firefight</div>
                </div>

                <a
                  href="/app"
                  className="inline-flex h-10 items-center justify-center rounded-md bg-foreground px-5 text-sm font-medium text-background shadow-sm transition-colors hover:bg-foreground/90"
                >
                  Continue to dashboard
                </a>
              </div>
            </div>
          </div>
        </main>
      </div>
    </>
  );
}
