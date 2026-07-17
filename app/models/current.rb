class Current < ActiveSupport::CurrentAttributes
  attribute :trace_id, :workspace, :api_key, :principal
end
