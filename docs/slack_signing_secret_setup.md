# Slack Signing Secret Setup

The Slack signing secret needs to be added to the Rails credentials for each environment.

## How to Add

For each environment (development, staging, production):

```bash
# Development
EDITOR="code --wait" bin/rails credentials:edit --environment development

# Staging
EDITOR="code --wait" bin/rails credentials:edit --environment staging

# Production
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

## Add this to each credentials file:

```yaml
slack:
  client_id: "existing..."
  client_secret: "existing..."
  signing_secret: "YOUR_SIGNING_SECRET_HERE"  # Add this line
```

## Where to Find the Signing Secret

1. Go to https://api.slack.com/apps
2. Select your Firefight app
3. Go to "Basic Information"
4. Scroll to "App Credentials"
5. Copy the "Signing Secret"

## Verify

After adding, verify with:

```ruby
Rails.application.credentials.slack[:signing_secret]
```
