import { useState } from "react"
import { Head, Link, router, usePage } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { SearchableMultiSelect, type SearchableMultiSelectOption } from "@/components/searchable-multi-select"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { PULL_REQUEST_REVIEWS_ON_OPEN } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { halonPullRequestReviewsPath, integrationsPath } from "@/lib/routes"
import type { PullRequestReviewSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface ReviewHost {
  name: string
  handle: string | null
  pickable: boolean
}

interface PullRequestReviewsPageProps extends SharedProps {
  settings: PullRequestReviewSettings
  hosts: ReviewHost[]
}

type OnOpen = (typeof PULL_REQUEST_REVIEWS_ON_OPEN)[keyof typeof PULL_REQUEST_REVIEWS_ON_OPEN]

const ON_OPEN_LABELS: Record<OnOpen, string> = {
  [PULL_REQUEST_REVIEWS_ON_OPEN.OFF]: "Only when someone asks",
  [PULL_REQUEST_REVIEWS_ON_OPEN.ALL]: "Every pull request when it opens, in every repository",
  [PULL_REQUEST_REVIEWS_ON_OPEN.CHOSEN]: "Every pull request when it opens, in the repositories you choose",
}

const ON_OPEN_CHOICES = Object.values(PULL_REQUEST_REVIEWS_ON_OPEN) as OnOpen[]

function isOnOpen(value: string): value is OnOpen {
  return (ON_OPEN_CHOICES as string[]).includes(value)
}

function hostLine(host: ReviewHost) {
  if (host.handle && host.pickable) {
    return `${host.name}: add ${host.handle} as a reviewer, or comment @${host.handle} review.`
  }
  if (host.handle) {
    return `${host.name}: comment @${host.handle} review.`
  }
  return `${host.name}: comment @firefight review.`
}

export default function PullRequestReviews() {
  const { settings, hosts } = usePage<PullRequestReviewsPageProps>().props
  const canManage = useCan("workspace")
  const [onOpen, setOnOpen] = useState<OnOpen>(isOnOpen(settings.pullRequestReviewsOnOpen) ? settings.pullRequestReviewsOnOpen : PULL_REQUEST_REVIEWS_ON_OPEN.OFF)
  const [chosen, setChosen] = useState<string[]>(settings.pullRequestReviewRepositories)
  const [saving, setSaving] = useState(false)
  const [errors, setErrors] = useState<Errors>({})

  const options: SearchableMultiSelectOption[] = settings.repositories.map((repository) => ({ value: repository, label: repository }))

  function chooseOnOpen(value: string) {
    if (isOnOpen(value)) {
      setOnOpen(value)
    }
  }

  function finish() {
    setSaving(false)
  }

  function succeed() {
    setErrors({})
  }

  function save() {
    setSaving(true)
    router.patch(
      halonPullRequestReviewsPath(),
      {
        pull_request_reviews_on_open: onOpen,
        pull_request_review_repositories: onOpen === PULL_REQUEST_REVIEWS_ON_OPEN.CHOSEN ? chosen : [],
      },
      { preserveScroll: true, onSuccess: succeed, onError: setErrors, onFinish: finish },
    )
  }

  return (
    <AuthenticatedLayout title="Pull requests">
      <Head title="Pull requests" />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <CardTitle>Asking Halon for a review</CardTitle>
            <CardDescription className="mt-1">
              Halon reviews a pull request when someone asks for it, and reviews the pull requests it opens itself. It
              posts one comment at once and keeps it up to date as it checks the change, comments on the lines it has
              something to say about, and adds a comment of its own for a serious problem so people are notified. Each
              new push to a pull request it reviewed is reviewed again, and it replies on each of its threads to say
              whether the fix holds.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {hosts.length > 0 ? (
              <ul className="flex flex-col gap-1 text-sm">
                {hosts.map((host) => (
                  <li key={host.name}>{hostLine(host)}</li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-muted-foreground">
                No code host is connected yet. Connect GitHub, GitLab or Bitbucket under{" "}
                <Link href={integrationsPath()} className="underline underline-offset-4">
                  Integrations
                </Link>{" "}
                and Halon can review its pull requests.
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Reviewing without being asked</CardTitle>
            <CardDescription className="mt-1">
              Which pull requests Halon reviews as soon as they open, without anyone asking. A draft is reviewed once it
              is marked ready. Each review spends from your AI budget like any other run.
            </CardDescription>
          </CardHeader>

          <CardContent className="flex flex-col gap-6">
            <RadioGroup value={onOpen} onValueChange={chooseOnOpen} className="gap-3" disabled={!canManage}>
              {ON_OPEN_CHOICES.map((choice) => (
                <div key={choice} className="flex items-center gap-3">
                  <RadioGroupItem value={choice} id={`on-open-${choice}`} />
                  <Label htmlFor={`on-open-${choice}`} className="font-normal">
                    {ON_OPEN_LABELS[choice]}
                  </Label>
                </div>
              ))}
            </RadioGroup>

            {onOpen === PULL_REQUEST_REVIEWS_ON_OPEN.CHOSEN && (
              <div className="flex max-w-prose flex-col gap-2">
                <Label className="text-foreground">Repositories</Label>
                <SearchableMultiSelect
                  value={chosen}
                  onValueChange={setChosen}
                  options={options}
                  placeholder="Choose repositories"
                  addMoreText="Add another repository"
                  searchPlaceholder="Search repositories"
                  emptyText="No repository on the map has that name"
                  disabled={!canManage}
                />
                {options.length === 0 && (
                  <p className="text-sm text-muted-foreground">
                    The map holds no repositories yet. They appear once a connected code host has been read.
                  </p>
                )}
                {errors.pull_request_review_repositories && (
                  <p className="text-sm text-destructive">{errors.pull_request_review_repositories}</p>
                )}
              </div>
            )}

            {canManage && (
              <div>
                <Button onClick={save} disabled={saving}>
                  Save
                </Button>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </AuthenticatedLayout>
  )
}
