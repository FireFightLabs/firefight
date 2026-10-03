import { useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { claimInviteCodePath } from "@/lib/routes";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import type { SharedProps } from "@/types";

interface InviteCodePageProps extends SharedProps {
  [key: string]: unknown;
  teamName: string;
}

export default function InviteCode() {
  const { teamName } = usePage<InviteCodePageProps>().props;
  const form = useForm({ code: "" });

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    form.post(claimInviteCodePath());
  };

  return (
    <AuthLayout title="Enter invite code" containerClassName="max-w-[420px]">
      <div>
        <CardHeader
          overline="Public beta"
          title="Enter invite code"
          subtitle={
            <>
              Firefight is in public beta. Installing to{" "}
              <span className="whitespace-nowrap font-medium text-fg-primary">
                {teamName}
              </span>{" "}
              requires a one-time invite code.
            </>
          }
        />
        <form className="space-y-3 text-left" onSubmit={submit}>
          <div className="space-y-2">
            <Label htmlFor="invite-code">Invite code</Label>
            <Input
              id="invite-code"
              name="code"
              value={form.data.code}
              onChange={(event) => form.setData("code", event.target.value)}
              placeholder="Enter your invite code"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
            />
          </div>
          <Button
            type="submit"
            className="w-full cursor-pointer"
            disabled={form.processing}
          >
            Continue
          </Button>
        </form>
        <div className="mt-6 border-t border-border pt-4">
          <p className="text-center text-xs leading-relaxed text-fg-muted">
            Don&apos;t have a code?{" "}
            <a
              href="mailto:support@firefight.app"
              className="font-semibold text-fg-primary underline decoration-border-control underline-offset-[3px] transition-colors duration-120 hover:decoration-fg-primary"
            >
              Request access
            </a>
            .
          </p>
        </div>
      </div>
    </AuthLayout>
  );
}
