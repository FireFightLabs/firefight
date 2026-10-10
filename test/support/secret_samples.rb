# One credential of each kind the transcript scrubber knows (IncidentTranscriptMessage::Scrubbing, plus a connection
# string with a password), for a test that checks none survives wherever text is kept.
module SecretSamples
  SAMPLES = {
    aws_key: "AKIAIOSFODNN7EXAMPLE",
    github_token: "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
    slack_token: "xoxb-1234567890-abcdefghij",
    anthropic_key: "sk-ant-api03-#{'X' * 90}",
    openai_key: "sk-proj-#{'a' * 60}",
    stripe_key: "sk_live_#{'A' * 30}",
    stripe_webhook: "whsec_#{'b' * 40}",
    google_api_key: "AIza#{'A' * 35}",
    sendgrid_key: "SG.#{'a' * 22}.#{'b' * 43}",
    mailgun_key: "key-#{'0123456789abcdef' * 2}",
    twilio_key: "SK#{'a' * 32}",
    digitalocean_token: "dop_v1_#{'a' * 64}",
    new_relic_key: "NRAK-#{'A' * 27}",
    npm_token: "npm_#{'a' * 36}",
    huggingface_token: "hf_#{'x' * 40}",
    github_pat: "github_pat_11ABCDEFG0#{'a' * 60}",
    supabase_secret: "sb_secret_#{'N7UND0Ug' * 3}",
    slack_webhook: "https://hooks.slack.com/services/T0123ABCD/B0123ABCD/#{'x' * 24}",
    bearer_token: "Bearer #{'q' * 40}",
    password_setting: "password=#{'p4ssw0rd' * 3}",
    bcrypt_hash: "$2b$12$#{'R9h/cIPz0gi.URNNX3kh2O' * 2}PST9/PgBkqquzi.Ss7KIUgO2t0jWMUW",
    scram_hash: "SCRAM-SHA-256$4096:#{'c2FsdHNhbHQ' * 2}$#{'c3RvcmVka2V5' * 3}:#{'c2VydmVya2V5' * 3}",
    jwt: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
    private_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAxYz\n-----END RSA PRIVATE KEY-----",
    credential_url: "postgres://app:s3cretpassw0rd@db.internal:5432/app"
  }.freeze
end
