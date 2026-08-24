import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { dashboardPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { FounderAvatar } from "@/pages/onboarding/components/welcome/founder-avatar";
import signatureUrl from "@/assets/uros-signature.png";
import type { SharedProps } from "@/types";

interface WelcomePageProps extends SharedProps {
  [key: string]: unknown;
  userName: string;
  workspaceName: string;
}

export default function Welcome({ userName, workspaceName }: WelcomePageProps) {
  const firstName = (userName?.trim().split(/\s+/)[0] ?? userName) || "there";

  return (
    <AuthLayout title="Welcome to Firefight">
      <Card variant="glow">
        <FireFightLogo className="mx-auto size-8" />

        <div className="mt-5 border-t border-primary/25" />

        <h1 className="mt-6 text-3xl font-medium tracking-tight text-foreground">
          You&apos;re in, <em className="italic">{firstName}.</em>
        </h1>

        <div className="mt-5 space-y-4 text-sm leading-relaxed text-foreground/85">
          <p>Thanks for giving Firefight a try.</p>

          <p>
            I built Firefight because incident tools became too complex and
            too expensive for most teams. Firefight stays inside Slack,
            where your team already works.
          </p>

          <p>Start small. Expand only when you need to.</p>

          <p>Firefight is open source and built in public.</p>

          <p>
            If you need anything, email me at{" "}
            <a
              href="mailto:uros@firefight.app"
              className="font-medium text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
            >
              uros@firefight.app
            </a>
            . I read every message.
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
          <img
            src={signatureUrl}
            alt=""
            aria-hidden="true"
            className="h-12 w-auto opacity-70"
          />
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

