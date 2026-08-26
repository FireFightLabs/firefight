json.set! collection_key do
  json.array! @options do |option|
    json.partial! "api/v1/options/option", option: option
  end
end
