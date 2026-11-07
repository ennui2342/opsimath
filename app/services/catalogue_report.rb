# Posts what changed in the catalogue to Discord's #catalogue (Mark,
# 2026-11-07): his edits, batched — every 15 minutes, once a burst has
# settled — and the overnight jobs' changes as a morning digest. Built
# from CatalogueEvent; each event is posted once.
module CatalogueReport
  SETTLE = 2.minutes # a burst of edits still going isn't cut in half
  MAX_LINES = 40      # Discord caps a description at 4096 characters
  JOB_LABELS = { "known_editions" => "Provider lookups", "sweep" => "Review queue", "mobile_snapshot" => "Phone app" }.freeze

  # Mark's edits since the last post. -> number posted
  def self.post_edits(now: Time.current)
    events = CatalogueEvent.unreported.from_web.where(created_at: ..(now - SETTLE)).order(:created_at).to_a
    return 0 if events.empty?

    lines = events.map { |e| "• #{e.summary}" }
    notify(title: "Catalogue: #{events.size} #{'change'.pluralize(events.size)}", lines:)
    mark(events, now)
  end

  # The background jobs' changes since the last digest. -> number posted
  def self.post_digest(now: Time.current)
    events = CatalogueEvent.unreported.from_jobs.order(:created_at).to_a
    return 0 if events.empty?

    notify(title: "Catalogue overnight", lines: digest_lines(events))
    mark(events, now)
  end

  def self.digest_lines(events)
    lines = []
    linked = events.select { |e| e.kind == "linked" }
    if linked.any?
      by_provider = linked.group_by { |e| e.details["provider"] }.map { |p, es| "#{es.size} in #{KnownEditionsRefresh::PROVIDER_LABELS.fetch(p, p)}" }
      lines << "**Books found by providers:** #{by_provider.join(', ')}"
      wanted = linked.select { |e| e.details["wanted"] }
      lines.concat(wanted.first(10).map { |e| "• ★ #{e.summary} (wanted)" })
    end
    printings = events.select { |e| e.kind == "new_printings" }
    if printings.any?
      lines << "**New printings:** #{printings.sum { |e| e.details['count'].to_i }} across #{printings.size} #{'book'.pluralize(printings.size)}"
      ordered = printings.sort_by { |e| e.details["wanted"] ? 0 : 1 }
      lines.concat(ordered.first(15).map { |e| "• #{'★ ' if e.details['wanted']}#{e.summary}" })
    end
    (events - linked - printings).group_by(&:origin).each do |origin, es|
      lines << "**#{JOB_LABELS.fetch(origin, origin.humanize)}:** #{es.map(&:summary).uniq.join('; ')}"
    end
    lines
  end

  def self.notify(title:, lines:)
    shown = lines.first(MAX_LINES)
    shown << "…and #{lines.size - MAX_LINES} more" if lines.size > MAX_LINES
    Notifications.notify(Notifications::Event.new(kind: :catalogue, level: :info, title:, channel: :catalogue,
                                                  description: shown.join("\n"), url: "#{Rails.application.config.x.public_url}/works", fields: {}))
  end

  def self.mark(events, now)
    CatalogueEvent.where(id: events.map(&:id)).update_all(reported_at: now)
    events.size
  end
end
