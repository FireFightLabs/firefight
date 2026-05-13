import { useState } from "react";
import { Head } from "@inertiajs/react";

import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { dashboardPath } from "@/lib/routes";
import type { SharedProps } from "@/types";

interface WelcomePageProps extends SharedProps {
  [key: string]: unknown;
  userName: string;
  workspaceName: string;
}

export default function Welcome({ userName, workspaceName }: WelcomePageProps) {
  const firstName = (userName?.trim().split(/\s+/)[0] ?? userName) || "there";
  const now = new Date();
  const dateStamp = `${String(now.getMonth() + 1).padStart(2, "0")}.${String(now.getFullYear()).slice(2)}`;

  return (
    <div className="dark">
      <Head title="Welcome to Firefight" />

      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(115,211,238,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(115,211,238,0.03)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-4 py-12 sm:px-6">
          <div style={{ width: "100%", maxWidth: "480px" }}>
            <div className="rounded-[14px] border border-primary/30 bg-card px-8 pb-8 pt-10 shadow-[0_1px_2px_0_rgba(0,0,0,0.2),0_20px_60px_0_rgba(0,0,0,0.4),0_0px_60px_0_rgba(115,211,238,0.06)] sm:px-10 sm:pb-10 sm:pt-12">
              {/* Header */}
              <div className="flex items-center justify-between">
                <FireFightLogo className="size-8" />
                <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground/60">
                  From the founder · {dateStamp}
                </span>
              </div>

              <div className="mt-5 border-t border-primary/25" />

              {/* Greeting */}
              <h1 className="mt-6 text-5xl font-medium leading-none tracking-tighter text-foreground">
                You&apos;re in, <em className="italic">{firstName}.</em>
              </h1>

              {/* Body */}
              <div className="mt-5 space-y-4">
                <p className="text-sm leading-relaxed text-foreground/88">
                  I built Firefight because incident tooling too often feels{" "}
                  <em className="italic">
                    bloated, opaque, and priced for large companies
                  </em>{" "}
                  — not the teams actually running systems.
                </p>

                <p className="text-sm leading-relaxed text-foreground/55">
                  It&apos;s meant to be straightforward. Declare the incident.
                  Create the response space. Keep the timeline clear. No
                  automation mazes, no setup walls — just the three things you
                  need when the pager goes.
                </p>

                <p className="text-sm leading-relaxed">
                  <span className="font-semibold text-foreground">
                    If something feels rough or missing, tell us.
                  </span>
                  <br />
                  <span className="text-foreground/55">
                    That&apos;s the feedback that matters now.
                  </span>
                </p>
              </div>

              {/* Signature */}
              <div className="mt-6 flex items-center justify-between border-t border-primary/25 py-4">
                <div className="flex items-center gap-3">
                  <Avatar />
                  <div className="leading-tight">
                    <p className="text-sm font-semibold tracking-tight text-foreground">
                      Uros Nikolic
                    </p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      Founder, Firefight
                    </p>
                  </div>
                </div>
                <SignatureMark className="h-9 w-[110px] text-foreground/50" />
              </div>

              {/* CTA */}
              <Button asChild className="mt-4 w-full cursor-pointer transition-shadow hover:shadow-[0_0_12px_rgba(115,211,238,0.2)]">
                <a href={dashboardPath()}>
                  Continue to {workspaceName}
                  <span aria-hidden="true" className="text-base">→</span>
                </a>
              </Button>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

function Avatar() {
  const [errored, setErrored] = useState(false);

  if (errored) {
    return (
      <span className="inline-flex size-11 shrink-0 items-center justify-center rounded-full bg-secondary text-xs font-semibold tracking-tight text-foreground">
        UN
      </span>
    );
  }

  return (
    <img
      src="https://i.pravatar.cc/96?img=12"
      alt="Uros Nikolic"
      onError={() => setErrored(true)}
      className="size-11 shrink-0 rounded-full object-cover ring-1 ring-border"
    />
  );
}

function SignatureMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 180 64"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <path
        d="M18 44c4-11 7-17 10-17 3 0 2 8 3 14 1 3 2 6 5 6 6 0 11-21 17-21 4 0 2 16 7 16 6 0 9-14 13-14 2 0 2 2 2 5 0 6 1 13 5 13 5 0 10-9 15-16 6-10 11-16 16-16 4 0 5 4 5 8 0 8-4 17-4 24 0 3 1 6 4 6 4 0 8-6 13-13"
        stroke="currentColor"
        strokeWidth="2.1"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M123 17c8 0 15 9 15 18 0 8-5 15-13 15-7 0-11-5-11-11 0-7 5-11 10-11 4 0 7 2 9 5"
        stroke="currentColor"
        strokeWidth="1.9"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M149 18c5 11 8 22 9 33 1-8 4-16 10-23 3-4 7-7 11-7 3 0 5 2 5 5 0 10-14 14-24 16"
        stroke="currentColor"
        strokeWidth="1.9"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
