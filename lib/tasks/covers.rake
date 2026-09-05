namespace :covers do
  desc "Seed COVER_CACHE_DIR from the covers already in the library so a later `goodreads:rebuild` reuses them instead of re-downloading ~2k provider images (the slow part of a rebuild). Keyed by the source URL each cover came from — EnrichmentRecord.fields['cover_image'] and each printing-choice candidate's cover_url. Safe to re-run: skips a URL already in the cache. See docs/INTEGRATIONS.md."
  task cache_export: :environment do
    dir = ENV["COVER_CACHE_DIR"].presence || abort("set COVER_CACHE_DIR to the directory to write into")
    FileUtils.mkdir_p(dir)

    written = skipped = missing = 0
    seen = Set.new

    stash = lambda do |url, attachment|
      return if url.blank? || !seen.add?(url)

      bytes_path, meta_path = HasCoverImage.cache_paths(url)
      if File.exist?(bytes_path) && File.exist?(meta_path)
        skipped += 1
        return
      end
      blob = attachment&.blob
      if blob.nil?
        missing += 1
        return
      end

      File.binwrite(bytes_path, blob.download)
      File.write(meta_path, JSON.generate(url: url, filename: blob.filename.to_s, content_type: blob.content_type || "image/jpeg"))
      written += 1
    end

    EnrichmentRecord.with_attached_cover_image.find_each do |record|
      stash.call(record.fields["cover_image"], record.cover_image_attachment)
    end

    PendingDecision.where(kind: "enrichment_printing_choice").with_attached_candidate_covers.find_each do |decision|
      url_by_pub = (decision.payload["candidates"] || []).index_by { |c| c["_isfdb_pub_id"].to_s }
      decision.candidate_covers_attachments.each do |attachment|
        stash.call(url_by_pub.dig(attachment.blob.filename.base, "cover_url"), attachment)
      end
    end

    puts "cover cache #{dir}: #{written} written, #{skipped} already cached, #{missing} with no blob on file"
  end
end
