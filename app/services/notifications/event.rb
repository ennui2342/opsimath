module Notifications
  # A plain value object — no behavior, no knowledge of any specific
  # backend. `fields` is a flat hash of label => value shown as extra
  # detail (e.g. title/isbn/shelf) by whichever notifier renders it.
  # `description` (Markdown, several lines) and `url` (the title's link)
  # are optional — a digest that's a list rather than a few fields.
  Event = Struct.new(:kind, :level, :title, :fields, :description, :url, keyword_init: true)
end
