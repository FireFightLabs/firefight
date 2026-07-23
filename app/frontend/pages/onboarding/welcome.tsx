import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { dashboardPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { FounderAvatar } from "@/pages/onboarding/components/welcome/founder-avatar";
import { SignatureMark } from "@/pages/onboarding/components/welcome/signature-mark";
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
            incident response looks like. We build in the open. The source
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
            <FounderAvatar />
            <div className="leading-tight">
              <p className="text-sm font-semibold tracking-tight text-foreground">
                Uros Nikolic
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Co-Founder, Firefight
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

