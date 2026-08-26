json.alert_sources @alert_sources do |alert_source|
  json.partial! "api/v1/alert_sources/alert_source", alert_source: alert_source
end
