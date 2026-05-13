import { Head } from "@inertiajs/react";

import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { FlashAlerts } from "@/components/flash-alerts";
import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";
import { TermsNotice } from "@/modules/auth/components/terms-notice";

export default function Login() {
  return (
    <div className="dark">
      <Head title="Sign in to Firefight" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(115,211,238,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(115,211,238,0.03)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[480px]">
            <Card variant="glow" className="text-center">
              <div className="mb-8 flex flex-col items-center space-y-4">
                <FireFightLogo />
                <div className="space-y-2">
                  <h1 className="text-2xl font-semibold tracking-tight text-foreground">
                    Sign in
                  </h1>
                  <p className="mx-auto text-sm leading-relaxed text-muted-foreground">
                    Connect your Slack workspace to get started.<br />
                    We&apos;ll walk you through setup on first sign-in.
                  </p>
                </div>
              </div>

              <FlashAlerts className="mb-4 text-left" />

              <SlackAuthButton />

              <TermsNotice />
            </Card>
          </div>
        </main>
      </div>
    </div>
  );
}
