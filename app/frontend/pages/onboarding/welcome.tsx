import { useState } from "react";

import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { dashboardPath } from "@/lib/routes";
import { AuthLayout } from "@/modules/auth/components/auth-layout";
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
    <AuthLayout title="Welcome to Firefight">
      <Card variant="glow">
        <div className="flex items-center justify-between">
          <FireFightLogo className="size-8" />
          <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground/60">
            From the founder · {dateStamp}
          </span>
        </div>

        <div className="mt-5 border-t border-primary/25" />

        <h1 className="mt-6 text-3xl font-medium tracking-tight text-foreground">
          You&apos;re in, <em className="italic">{firstName}.</em>
        </h1>

        <div className="mt-5 space-y-4 text-sm leading-relaxed text-foreground/85">
          <p>
            I built Firefight because every incident tool I&apos;d worked
            with felt the same way: bloated, complicated, priced for
            enterprise. Not built for the teams actually wading into alerts
            at 3am.
          </p>

          <p>
            Firefight is simple to start and built to grow with you. Start
            small, add the workflows you need as your team learns what good
            incident response looks like. We build in the open — the source
            is on GitHub, you can see what we&apos;re working on, and you
            can push back when something feels off. That&apos;s how dev
            tools should be built.
          </p>

          <p>
            If something feels rough or you need a hand, message me
            directly. We&apos;re a small team, we read everything, and we
            mean that.
          </p>
        </div>

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

        <Button asChild className="mt-4 w-full cursor-pointer transition-shadow hover:shadow-[0_0_12px_rgba(115,211,238,0.2)]">
          <a href={dashboardPath()}>
            Continue to {workspaceName}
            <span aria-hidden="true" className="text-base">→</span>
          </a>
        </Button>
      </Card>
    </AuthLayout>
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
