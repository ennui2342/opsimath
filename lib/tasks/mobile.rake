namespace :mobile do
  desc "Rebuild the offline shop-lookup snapshot now (docs/MOBILE.md)"
  task snapshot: :environment do
    snapshot = MobileSnapshotJob.perform_now
    puts "snapshot v#{snapshot.version}: #{snapshot.entry_count} entries, #{snapshot.byte_size} bytes"
  end

  desc "Generate the :thumb variant for every existing edition/wishlist cover, so the nightly snapshot build does no image work"
  task warm_thumbs: :environment do
    warmed = 0
    [ Edition, WishlistItem ].each do |model|
      model.joins(:cover_image_attachment).find_each do |record|
        record.cover_image.variant(:thumb).processed
        warmed += 1
      rescue StandardError => e
        warn "  #{model}##{record.id}: #{e.message}"
      end
    end
    puts "warmed #{warmed} :thumb variants"
  end

  desc "Backfill covers for wishlist items that predate cover capture (RSS feed + Goodreads page og:image)"
  task backfill_wishlist_covers: :environment do
    puts MobileWishlistCoverBackfillJob.perform_now
  end
end
