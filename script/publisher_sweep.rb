# =============================================================================
# Retroactive publisher-heuristic sweep  (opsimath, 2026-09-02)
#
# Follows the plan_publisher change in commits 70462f1 + 380f5e2:
#   - distinct-name substring containments ("Futura Orbit" vs "Orbit") are
#     now conflicts, not silent merges
#   - imprint/parent joined names ("Gollancz / Orion") merge toward the
#     fuller form, like territory qualifiers
#
# Order of operations:
#   1. CAT2 - restore publisher + field-source from the pre-ISFDB source on
#      editions where ISFDB had SILENTLY overwritten with a form the new
#      rule counts as distinct ("Spectra" -> "Bantam Spectra" etc.), so the
#      reprocess in step 3 raises a proper review decision for them.
#   2. Delete every pending source=isfdb enrichment_conflict decision.
#      (0 enrichment_conflict decisions have ever been resolved and the
#      model carries no draft/partial-review state, so this loses nothing
#      but row ids.)  goodreads-sourced and reread decisions are untouched.
#   3. Re-run IsfdbEditionEnricher.reprocess over every edition with an
#      ISFDB EnrichmentRecord - regenerates the deleted decisions under the
#      new rule and raises the ones the old rule had swallowed.
#
# Run once with DRY_RUN = true to see the plan, then set it false and rerun.
# =============================================================================

DRY_RUN = true

def plan_for(publisher_value, proposed)
  Enrichment::IsfdbEditionEnricher.new(Edition.new(publisher: publisher_value), client: nil)
    .send(:plan_publisher, proposed)
end

isfdb_records = EnrichmentRecord.where(provider: "isfdb").includes(entity: :enrichment_records).to_a

cat2         = []  # [edition, source_provider, restore_value, isfdb_value]
auto_refine  = []  # [edition, current, isfdb_value]  -> reprocess will overwrite publisher with isfdb_value

isfdb_records.each do |r|
  e = r.entity
  next unless e.is_a?(Edition)
  ip = r.fields["publisher"]
  next if ip.blank?

  if e.field_sources["publisher"] == "isfdb"
    o = e.enrichment_records.reject { |rec| rec.provider == "isfdb" }
          .find { |rec| rec.fields["publisher"].present? && plan_for(rec.fields["publisher"], ip).action == :conflict }
    cat2 << [ e, o.provider, o.fields["publisher"], ip ] if o
  end

  auto_refine << [ e, e.publisher, ip ] if plan_for(e.publisher, ip).action == :refine
end

doomed = PendingDecision.where(kind: "enrichment_conflict", status: "pending")
                        .where("payload ->> 'source' = 'isfdb'")

puts "isfdb EnrichmentRecords:                            #{isfdb_records.size}"
puts "CAT2 restore (isfdb had silently overwritten):      #{cat2.size}"
cat2.each { |e, prov, ov, ip| puts "   ed##{e.id}  #{prov}=#{ov.inspect}   isfdb had set #{ip.inspect}" }
puts "joined-name refinements reprocess will auto-apply:  #{auto_refine.size}"
auto_refine.first(40).each { |e, cur, ip| puts "   ed##{e.id}  #{cur.inspect}  ->  #{ip.inspect}" }
puts "   ...(#{auto_refine.size - 40} more)" if auto_refine.size > 40
puts "pending isfdb enrichment_conflict decisions to delete: #{doomed.count}"

if DRY_RUN
  puts "\n[dry-run] nothing written. Set DRY_RUN = false and rerun to apply."
else
  ActiveRecord::Base.transaction do
    cat2.each { |e, prov, ov, _ip| e.update!(publisher: ov, field_sources: e.field_sources.merge("publisher" => prov)) }
    puts "restored #{cat2.size} publishers"
    n = doomed.count
    doomed.destroy_all
    puts "deleted #{n} pending isfdb enrichment_conflict decisions"
  end

  ok = 0
  errs = []
  isfdb_records.each_with_index do |r, i|
    e = r.entity
    next unless e.is_a?(Edition)
    begin
      Enrichment::IsfdbEditionEnricher.reprocess(e, r.raw_payload)
      ok += 1
    rescue => ex
      errs << [ e.id, ex.class.name, ex.message ]
    end
    puts "  reprocessed #{i + 1}/#{isfdb_records.size}" if ((i + 1) % 250).zero?
  end
  puts "reprocessed #{ok} editions, #{errs.size} errors"
  errs.first(20).each { |id, k, m| puts "  ed##{id}: #{k} #{m}" }

  final = PendingDecision.where(kind: "enrichment_conflict", status: "pending")
  puts "\npending enrichment_conflict now: #{final.count} (isfdb: #{final.where("payload ->> 'source' = 'isfdb'").count})"
  puts "  with publisher in fields:      #{final.select { |d| d.payload['fields']&.include?('publisher') }.size}"
end
