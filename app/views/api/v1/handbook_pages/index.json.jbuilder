json.pages @pages do |page|
  json.partial! "api/v1/handbook_pages/page", page: page
end
