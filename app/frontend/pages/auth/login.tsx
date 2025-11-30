import { Head } from '@inertiajs/react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { SlackAuthButton } from '@/components/auth/slack-auth-button'

export default function Login() {
  return (
    <>
      <Head title="Sign in to Firefight" />
      <div className="min-h-screen flex items-center justify-center bg-background p-4">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <CardTitle className="text-2xl">Welcome to Firefight</CardTitle>
            <CardDescription>
              Sign in with your Slack workspace to get started
            </CardDescription>
          </CardHeader>
          <CardContent>
            <SlackAuthButton />
          </CardContent>
        </Card>
      </div>
    </>
  )
}
