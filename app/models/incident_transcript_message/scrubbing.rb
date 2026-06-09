module IncidentTranscriptMessage::Scrubbing
  extend ActiveSupport::Concern

  SECRET_PATTERNS = {
    aws_key:            /\b(AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}\b/,
    github_token:       /\bgh[pousr]_[A-Za-z0-9]{36}\b/,
    slack_token:        /\bxox[baprse]-[A-Za-z0-9-]{10,}\b/,
    anthropic_key:      /\bsk-ant-api\d{2}-[A-Za-z0-9_-]{80,}\b/,
    openai_key:         /\bsk-(proj-)?[A-Za-z0-9_-]{40,}\b/,
    stripe_key:         /\b(sk|rk)_(live|test)_[A-Za-z0-9]{24,}\b/,
    stripe_webhook:     /\bwhsec_[A-Za-z0-9]{32,}\b/,
    google_api_key:     /\bAIza[0-9A-Za-z_-]{35}\b/,
    sendgrid_key:       /\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b/,
    mailgun_key:        /\bkey-[0-9a-zA-Z]{32}\b/,
    twilio_key:         /\bSK[0-9a-fA-F]{32}\b/,
    digitalocean_token: /\bdop_v1_[a-f0-9]{64}\b/,
    new_relic_key:      /\bNRAK-[A-Z0-9]{27}\b/,
    npm_token:          /\bnpm_[A-Za-z0-9]{36}\b/,
    huggingface_token:  /\bhf_[A-Za-z0-9]{32,}\b/,
    jwt:                /\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/,
    private_key:        /-----BEGIN[ A-Z]*PRIVATE KEY-----.*?-----END[ A-Z]*PRIVATE KEY-----/m
  }.freeze

  included do
    before_save :scrub_content, if: :content_changed?
  end

  private

  def scrub_content
    SECRET_PATTERNS.each do |name, pattern|
      next unless content.match?(pattern)
      self.content = content.gsub(pattern, "[REDACTED:#{name}]")
      self.scrubbed = true
    end
  end
end
