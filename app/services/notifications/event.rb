module Notifications
  # A plain value object — no behavior, no knowledge of any specific
  # backend. `fields` is a flat hash of label => value shown as extra
  # detail (e.g. title/isbn/shelf) by whichever notifier renders it.
  Event = Struct.new(:kind, :level, :title, :fields, keyword_init: true)
end
