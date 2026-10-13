SolidWorkflow.configure do |config|
  # Retrying these produces the same outcome.
  config.terminal_error_classes += %w[
    AdapterError::AuthRevoked
    AdapterError::UnsafeDownloadHost
    AdapterError::RestrictedAction
    Workflow::Run::Refused
    Workflow::Edit::Refused
  ]
end
