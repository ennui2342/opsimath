# The other printings ISFDB knows for a work (as ISBN-13s), cached so the
# mobile snapshot build reads one table instead of fanning ~2,000 live
# lookups at the ISFDB adapter on every build — that fan-out is slow and,
# under a wall-clock cap, non-deterministic (a contended build silently
# drops the works it didn't reach). Refreshed off the critical path by
# Isfdb::SiblingIsbnRefresh.
#
# `queried_isbns` records which of the work's ISBNs produced this result,
# so a work that later gains an ISBN is re-queried rather than trusted
# stale. Pure derived data — safe to truncate.
class WorkSiblingIsbns < ApplicationRecord
  self.primary_key = :work_id

  # {work_id => [isbn13, ...]} for the works we have, non-empty only.
  def self.for_works(work_ids)
    where(work_id: work_ids).where.not(isbn13s: []).pluck(:work_id, :isbn13s).to_h
  end

  def stale?(current_isbns, max_age:)
    refreshed_at < max_age.ago || queried_isbns.sort != current_isbns.sort
  end
end
