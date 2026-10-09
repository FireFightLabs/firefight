import { Link, router, useForm, usePage } from "@inertiajs/react";
import type { HttpResponse } from "@inertiajs/core";
import { useState } from "react";
import type { ChangeEvent, FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { loginPath, reuseSignupWorkspacePath, signInWithSlackPath, signupWorkspacePath } from "@/lib/routes";
import { retryWait, TOO_MANY_STATUS } from "@/lib/http";
import { formatDate, formatTime } from "@/lib/formatters";
import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import type { SharedProps } from "@/types";

interface SignupWorkspacePageProps extends SharedProps {
  [key: string]: unknown;
  email: string;
  suggestedName: string;
  nameMaxLength: number;
  inviteRequired: boolean;
  // Someone new by email has no name yet.
  askName: boolean;
  // A Slack sign-in by someone who owns workspaces without Slack, who carries on in one of them or makes another.
  unconnectedWorkspaces: UnconnectedWorkspace[];
}

interface UnconnectedWorkspace {
  id: string;
  name: string;
  createdAt: string;
}

const LINK_CLASS =
  "font-semibold text-fg-primary underline decoration-border-control underline-offset-[3px] transition-colors duration-120 hover:decoration-fg-primary";

export default function SignupWorkspace() {
  const { email, suggestedName, nameMaxLength, inviteRequired, askName, unconnectedWorkspaces } =
    usePage<SignupWorkspacePageProps>().props;
  const choosing = unconnectedWorkspaces.length > 0;
  const [creatingNew, setCreatingNew] = useState(false);
  const form = useForm({ name: suggestedName, invite_code: "", person_name: "", create_new: choosing });

  function createNew() {
    setCreatingNew(true);
  }

  if (choosing && !creatingNew) {
    return (
      <ChooseWorkspace workspaces={unconnectedWorkspaces} teamName={suggestedName} email={email} onCreateNew={createNew} />
    );
  }

  function changePersonName(event: ChangeEvent<HTMLInputElement>) {
    form.setData("person_name", event.target.value);
  }

  function changeName(event: ChangeEvent<HTMLInputElement>) {
    form.setData("name", event.target.value);
  }

  function changeInviteCode(event: ChangeEvent<HTMLInputElement>) {
    form.setData("invite_code", event.target.value);
  }

  // A throttled request answers with a plain page, which would otherwise open over the form.
  function handleHttpException(response: HttpResponse) {
    if (response.status !== TOO_MANY_STATUS) {
      return;
    }
    form.setError("name", [`Too many workspaces were created from this network. Try again ${retryWait(response)}.`]);
    return false;
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    form.post(signupWorkspacePath(), { onHttpException: handleHttpException });
  }

  return (
    <AuthLayout title="Name your workspace" containerClassName="max-w-[420px]">
      <div>
        <CardHeader
          title="Name your workspace"
          subtitle="This is where your team's incidents, services and history live. You can connect Slack next."
        />
        <form className="space-y-4 text-left" onSubmit={submit} noValidate>
          {askName ? (
            <div className="space-y-2">
              <Label htmlFor="person-name">Your name</Label>
              <Input
                id="person-name"
                name="person_name"
                value={form.data.person_name}
                onChange={changePersonName}
                placeholder="Alex Rivera"
                autoComplete="name"
                autoFocus
                aria-invalid={form.errors.person_name ? true : undefined}
              />
              {form.errors.person_name ? <p className="text-sm text-destructive">{form.errors.person_name}</p> : null}
            </div>
          ) : null}
          <div className="space-y-2">
            <Label htmlFor="workspace-name">Workspace name</Label>
            <Input
              id="workspace-name"
              name="name"
              value={form.data.name}
              onChange={changeName}
              placeholder="Acme"
              maxLength={nameMaxLength}
              autoComplete="organization"
              autoFocus={!askName}
              aria-invalid={form.errors.name ? true : undefined}
            />
            {form.errors.name ? <p className="text-sm text-destructive">{form.errors.name}</p> : null}
          </div>
          {inviteRequired ? (
            <div className="space-y-2">
              <Label htmlFor="invite-code">Invite code</Label>
              <Input
                id="invite-code"
                name="invite_code"
                value={form.data.invite_code}
                onChange={changeInviteCode}
                placeholder="Enter your invite code"
                autoCapitalize="characters"
                autoCorrect="off"
                spellCheck={false}
                aria-invalid={form.errors.invite_code ? true : undefined}
              />
              {form.errors.invite_code ? (
                <p className="text-sm text-destructive">{form.errors.invite_code}</p>
              ) : (
                <p className="text-xs text-fg-muted">
                  Firefight is in public beta. Don&apos;t have a code?{" "}
                  <a href="mailto:support@firefight.app" className={LINK_CLASS}>
                    Request access
                  </a>
                  .
                </p>
              )}
            </div>
          ) : null}
          <Button type="submit" className="h-11 w-full cursor-pointer font-medium" disabled={form.processing}>
            Create workspace
          </Button>
        </form>
        <div className="mt-6 space-y-3 border-t border-border pt-4 text-center text-xs leading-relaxed text-fg-muted">
          <p>
            Is your team already on Firefight?{" "}
            <a href={signInWithSlackPath()} className={LINK_CLASS}>
              Sign in with Slack
            </a>{" "}
            or ask an admin to invite you.
          </p>
          <SignedInAs email={email} />
        </div>
      </div>
    </AuthLayout>
  );
}

interface ChooseWorkspaceProps {
  workspaces: UnconnectedWorkspace[];
  teamName: string;
  email: string;
  onCreateNew: () => void;
}

// Workspaces of theirs have no Slack yet, even just one, so whether this Slack joins one of them or a new one is theirs
// to say.
function ChooseWorkspace({ workspaces, teamName, email, onCreateNew }: ChooseWorkspaceProps) {
  const [choosingId, setChoosingId] = useState<string | null>(null);
  const intro =
    workspaces.length === 1
      ? "This workspace of yours is not connected to Slack yet. Choose it to connect it to"
      : "These workspaces of yours are not connected to Slack yet. Choose the one to connect to";

  function stopChoosing() {
    setChoosingId(null);
  }

  function choose(workspaceId: string) {
    setChoosingId(workspaceId);
    router.post(reuseSignupWorkspacePath(), { workspace_id: workspaceId }, { onFinish: stopChoosing });
  }

  return (
    <AuthLayout title="Choose your workspace" containerClassName="max-w-[420px]">
      <div>
        <CardHeader
          title="Choose your workspace"
          subtitle={
            <>
              {intro}{" "}
              <span className="font-medium text-fg-primary">{teamName || "this Slack"}</span>.
            </>
          }
        />
        <ul className="space-y-2">
          {workspaces.map((workspace) => (
            <li key={workspace.id}>
              <Button
                type="button"
                variant="outline"
                className="h-auto w-full cursor-pointer flex-col items-start gap-0.5 py-2.5 font-medium"
                disabled={choosingId !== null}
                onClick={() => choose(workspace.id)}
              >
                <span>{workspace.name}</span>
                <span className="text-xs font-normal text-fg-muted">
                  Created {formatDate(workspace.createdAt)} at {formatTime(workspace.createdAt)}
                </span>
              </Button>
            </li>
          ))}
        </ul>
        <p className="mt-4 text-center text-xs">
          <button type="button" className={`cursor-pointer ${LINK_CLASS}`} onClick={onCreateNew}>
            Create a new workspace
          </button>
        </p>
        <div className="mt-6 border-t border-border pt-4 text-center text-xs leading-relaxed text-fg-muted">
          <SignedInAs email={email} />
        </div>
      </div>
    </AuthLayout>
  );
}

function SignedInAs({ email }: { email: string }) {
  return (
    <p>
      Signed in as <span className="font-medium text-fg-primary">{email}</span>.{" "}
      <Link href={loginPath()} className={LINK_CLASS}>
        Use another account
      </Link>
    </p>
  );
}
