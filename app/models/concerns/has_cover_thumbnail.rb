# A `cover_image` Active Storage attachment plus one shared, declared
# `:thumb` variant — ~120x180 WebP, the size the offline shop-lookup PWA
# ships (docs/MOBILE.md constraint 2). `preprocessed: true` so the thumb
# is generated when the cover is attached rather than on first request,
# which keeps the snapshot export a plain copy with no image work.
module HasCoverThumbnail
  extend ActiveSupport::Concern

  THUMB_VARIANT = { resize_to_limit: [ 120, 180 ], format: :webp, saver: { quality: 80 } }.freeze

  included do
    has_one_attached :cover_image do |attachable|
      attachable.variant :thumb, **THUMB_VARIANT, preprocessed: true
    end
  end
end
