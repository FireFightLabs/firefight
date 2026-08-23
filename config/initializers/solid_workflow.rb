SolidWorkflow.configure do |config|
  # App-specific terminal errors, retrying these produces the same outcome
  config.terminal_error_classes += %w[
    AdapterError::AuthRevoked
    AdapterError::UnsafeDownloadHost
    AdapterError::RestrictedAction
  ]
end
