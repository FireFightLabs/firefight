import { signInWithSlackPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { SlackButton } from "@/components/auth/slack-button";
import { TermsNotice } from "@/pages/login/components/terms-notice";

export default function Login() {
  return (
    <AuthLayout title="Sign in to Firefight">
      <div className="text-center">
        <CardHeader
          title="Sign in"
          subtitle={
            <>
              Connect your Slack workspace to get started.
              <br />
              We&apos;ll walk you through setup on first sign-in.
            </>
          }
        />

        <SlackButton
          href={signInWithSlackPath()}
          label="Continue with Slack"
          className="mx-auto max-w-[320px]"
        />

        <TermsNotice />
      </div>
    </AuthLayout>
  );
}
