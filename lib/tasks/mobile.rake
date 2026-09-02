namespace :mobile do
  desc "Rebuild the offline shop-lookup snapshot now (docs/MOBILE.md)"
  task snapshot: :environment do
    snapshot = MobileSnapshotJob.perform_now
    puts "snapshot v#{snapshot.version}: #{snapshot.entry_count} entries, #{snapshot.byte_size} bytes"
  end

  desc "Cache every :thumb-variant's bytes (MobileThumb) so the snapshot build does no image work or blob I/O — seeds from the current snapshot, then fills gaps from Active Storage"
  task warm_thumbs: :environment do
    seeded = MobileThumb.seed_from_snapshot
    seen = filled = 0
    [ Edition, WishlistItem ].each do |model|
      model.joins(:cover_image_attachment).includes(cover_image_attachment: :blob).find_each do |record|
        seen += 1
        variant = record.cover_image.variant(:thumb).processed
        next if MobileThumb.exists?(blob_key: variant.key)

        MobileThumb.store(variant.key, variant.download)
        filled += 1
      rescue StandardError => e
        warn "  #{model}##{record.id}: #{e.message}"
      end
    end
    puts "seeded #{seeded} from snapshot, filled #{filled} gaps of #{seen} covers (#{MobileThumb.count} cached)"
  end

  desc "Backfill covers for wishlist items that predate cover capture (RSS feed image, then ISFDB cover by ISBN)"
  task backfill_wishlist_covers: :environment do
    puts MobileWishlistCoverBackfillJob.perform_now
  end
end
