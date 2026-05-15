import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { FlashAlerts } from "@/components/flash-alerts";
import { AuthLayout } from "@/modules/auth/components/auth-layout";
import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";
import { TermsNotice } from "@/modules/auth/components/terms-notice";

export default function Login() {
  return (
    <AuthLayout title="Sign in to Firefight">
      <Card variant="glow" className="text-center">
        <div className="mb-8 flex flex-col items-center space-y-4">
          <FireFightLogo />
          <div className="space-y-2">
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">
              Sign in
            </h1>
            <p className="mx-auto text-sm leading-relaxed text-muted-foreground">
              Connect your Slack workspace to get started.
              <br />
              We&apos;ll walk you through setup on first sign-in.
            </p>
          </div>
        </div>
        <FlashAlerts className="mb-4 text-left" />
        <SlackAuthButton />
        <TermsNotice />
      </Card>
    </AuthLayout>
  );
}
