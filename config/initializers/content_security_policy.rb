Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.img_src     :self, :https, :data
    policy.font_src    :self, :https, :data
    policy.connect_src :self, :https
    policy.object_src  :none
    policy.frame_ancestors :none

    if Rails.env.development?
      policy.script_src *policy.script_src, :unsafe_eval, "http://#{ViteRuby.config.host_with_port}"
      policy.connect_src *policy.connect_src, "ws://#{ViteRuby.config.host_with_port}"
    end
  end

  # Report only until the violations seen in browser CSP reports are cleared.
  config.content_security_policy_report_only = true

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
