import { Head } from "@inertiajs/react";

import { FireFightLogo } from "@/components/fire-fight-logo";
import { FlashAlerts } from "@/components/flash-alerts";
import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";

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
            <div className="relative rounded-[14px] border border-[rgba(115,211,238,0.3)] bg-card px-8 pb-8 pt-10 text-center shadow-[0_1px_2px_0_rgba(0,0,0,0.2),0_20px_60px_0_rgba(0,0,0,0.4),0_0px_60px_0_rgba(115,211,238,0.06)] sm:px-10 sm:pb-10 sm:pt-12">
              <div className="mb-8 flex flex-col items-center space-y-4">
                <FireFightLogo />
                <div className="space-y-2">
                  <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                    Sign in
                  </h1>
                  <p className="mx-auto text-[1.0625rem] leading-relaxed text-muted-foreground">
                    Connect your Slack workspace to get started.<br />
                    We&apos;ll walk you through setup on first sign-in.
                  </p>
                </div>
              </div>

              <FlashAlerts className="mb-4 text-left" />

              <SlackAuthButton />

              <div className="mt-6 border-t pt-4" style={{ borderColor: "rgba(115,211,238,0.25)" }}>
                <p className="text-xs leading-relaxed text-muted-foreground">
                  By continuing, you agree to our
                </p>
                <p className="mt-1 text-xs leading-relaxed">
                  <a
                    href="https://firefight.app/terms"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                  >
                    Terms
                  </a>
                  <span className="text-muted-foreground"> and </span>
                  <a
                    href="https://firefight.app/privacy"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                  >
                    Privacy Policy
                  </a>
                </p>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}
