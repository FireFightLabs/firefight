import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { Button } from "@/components/ui/button";
import { dashboardPath, onboardingInstallPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { FounderAvatar } from "@/pages/onboarding/components/welcome/founder-avatar";
import signatureUrl from "@/assets/uros-signature.png";
import type { SharedProps } from "@/types";

interface WelcomePageProps extends SharedProps {
  [key: string]: unknown;
  userName: string;
  workspaceName: string;
  // A workspace created from a Slack sign-in goes on to connect that team.
  connectSlack: boolean;
}

export default function Welcome({ userName, workspaceName, connectSlack }: WelcomePageProps) {
  const firstName = (userName?.trim().split(/\s+/)[0] ?? userName) || "there";

  return (
    <AuthLayout title="Welcome to Firefight">
      <Card variant="feature">
        <FireFightLogo className="mx-auto size-8" />

        <div className="mt-5 border-t border-border" />

        <h1 className="mt-6 text-3xl font-medium tracking-tight text-fg-headline">
          You&apos;re in, <em className="italic">{firstName}.</em>
        </h1>

        <div className="mt-5 space-y-4 text-sm leading-relaxed text-fg-body">
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
              className="font-medium text-fg-primary underline decoration-border-control underline-offset-[3px] transition-colors duration-120 hover:decoration-fg-primary"
            >
              uros@firefight.app
            </a>
            . I read every message.
          </p>
        </div>

        <div className="mt-6 flex items-center justify-between border-t border-border py-4">
          <div className="flex items-center gap-3">
            <FounderAvatar />
            <div className="leading-tight">
              <p className="text-sm font-semibold tracking-tight text-fg-primary">
                Uros Nikolic
              </p>
              <p className="mt-0.5 text-xs text-fg-muted">
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

        <Button asChild className="mt-4 w-full cursor-pointer">
          <a href={connectSlack ? onboardingInstallPath() : dashboardPath()}>
            {connectSlack ? "Connect Slack" : `Continue to ${workspaceName}`}
            <span aria-hidden="true" className="text-base">→</span>
          </a>
        </Button>
      </Card>
    </AuthLayout>
  );
}

