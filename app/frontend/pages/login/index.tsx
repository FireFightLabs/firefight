import { usePage } from "@inertiajs/react";

import { signInWithGooglePath, signInWithSlackPath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { GoogleButton } from "@/components/auth/google-button";
import { SlackButton } from "@/components/auth/slack-button";
import { EmailSignInForm } from "@/pages/login/components/email-sign-in-form";
import { TermsNotice } from "@/pages/login/components/terms-notice";
import type { SharedProps } from "@/types";

interface LoginPageProps extends SharedProps {
  [key: string]: unknown;
  googleSignIn: boolean;
  emailSignIn: boolean;
}

function methodsLine(googleSignIn: boolean, emailSignIn: boolean): string {
  const methods = ["Slack", googleSignIn ? "Google" : null, emailSignIn ? "a link sent to your email" : null].filter(
    (method): method is string => method !== null,
  );
  const last = methods.pop();
  return `Use ${methods.join(", ")} or ${last}.`;
}

export default function Login() {
  const { googleSignIn, emailSignIn } = usePage<LoginPageProps>().props;
  const slackOnly = !googleSignIn && !emailSignIn;

  return (
    <AuthLayout title="Sign in to Firefight">
      <div className="text-center">
        <CardHeader
          title="Sign in"
          subtitle={
            slackOnly ? (
              <>
                Connect your Slack workspace to get started.
                <br />
                We&apos;ll walk you through setup on first sign-in.
              </>
            ) : (
              methodsLine(googleSignIn, emailSignIn)
            )
          }
        />

        <div className="mx-auto flex max-w-[320px] flex-col gap-3">
          <SlackButton href={signInWithSlackPath()} label="Continue with Slack" />

          {googleSignIn ? (
            <GoogleButton href={signInWithGooglePath()} label="Continue with Google" />
          ) : null}

          {emailSignIn ? (
            <>
              <div className="flex items-center gap-3 py-2 text-xs text-fg-muted" aria-hidden="true">
                <span className="h-px flex-1 bg-border" />
                or
                <span className="h-px flex-1 bg-border" />
              </div>
              <EmailSignInForm />
            </>
          ) : null}
        </div>

        <TermsNotice />
      </div>
    </AuthLayout>
  );
}
