# What changed in the catalogue, to Discord's #opsimath (Mark,
# 2026-11-07; redesigned 2026-11-15). Built from CatalogueEvent; each event
# is posted once.
#
# - Every 15 minutes, once a burst has settled: **your changes** (Mark's
#   edits on the web) and **corrections** (one-off fixes run by hand —
#   CatalogueEvent.correction?), straight away rather than overnight.
# - Each morning: what the background jobs did.
#
# Each section is its own embed with a heading and colour, in the words
# Mark and opsimath share: a **work** (the book: its title, ISFDB title
# record, type, series) and an **edition** (his copy: its printing,
# publisher, date, cover). Nothing is cut off: a long section continues in
# further embeds, "(2 of 3)", over as many messages as Discord needs
# (Notifications::DiscordNotifier.pack).
module CatalogueReport
  SETTLE = 2.minutes # a burst of edits still going isn't cut in half
  DESCRIPTION_CHARS = 4000 # Discord caps an embed description at 4096
  COLORS = { works: 0x3B82F6, wishlist: 0xEAB308, editions: 0x22C55E, new_editions: 0xA855F7,
             housekeeping: 0x6B7280, corrections: 0xF97316, yours: 0x5865F2 }.freeze
  HOUSEKEEPING_LABELS = { "sweep" => "Review queue", "mobile_snapshot" => "Phone app" }.freeze

  Section = Struct.new(:title, :color, :lines)

  # Mark's edits and hand-run corrections since the last post. -> number posted
  def self.post_edits(now: Time.current)
    events = CatalogueEvent.unreported.where(created_at: ..(now - SETTLE))
                           .merge(CatalogueEvent.from_web.or(CatalogueEvent.corrections)).order(:created_at).to_a
    return 0 if events.empty?

    corrections, yours = events.partition { |e| e.details["by"] == "correction" }
    notify(title: "Catalogue: #{events.size} #{'change'.pluralize(events.size)}",
           sections: [ Section.new("Your changes", COLORS[:yours], yours.map(&:summary)),
                       Section.new("Corrections (run by hand)", COLORS[:corrections], corrections.map(&:summary)) ])
    mark(events, now)
  end

  # The background jobs' changes since the last digest. -> number posted
  def self.post_digest(now: Time.current)
    events = CatalogueEvent.unreported.from_jobs.order(:created_at).to_a
    return 0 if events.empty?

    notify(title: "Catalogue overnight", sections: digest_sections(events))
    mark(events, now)
  end

  def self.digest_sections(events)
    take = ->(&pick) { events.select(&pick).tap { |picked| events -= picked } }
    wanted_first = ->(list) { list.sort_by { |e| e.details["wanted"] ? 0 : 1 } }

    found = wanted_first.(take.() { |e| e.kind == "linked" })
    relinked = take.() { |e| e.kind == "relinked" }
    retitled = take.() { |e| e.kind == "retitled" }
    series = take.() { |e| e.kind == "series" }
    wishlist = take.() { |e| e.kind == "wanted" }
    updated = take.() { |e| e.kind == "refreshed" }
    new_editions = wanted_first.(take.() { |e| e.kind == "new_printings" })

    [
      Section.new("Works found in ISFDB or Open Library", COLORS[:works],
                  found.map { |e| "#{'★ ' if e.details['wanted']}#{e.summary}#{' (on your wishlist)' if e.details['wanted']}" }),
      Section.new("Works linked to a different ISFDB title record", COLORS[:works], relinked.map(&:summary)),
      Section.new("Works retitled", COLORS[:works], retitled.map(&:summary)),
      Section.new("Works' series", COLORS[:works], series.map { |e| e.summary.delete_suffix(" (from ISFDB)") }),
      Section.new("Added to your wishlist", COLORS[:wishlist], wishlist.map(&:summary)),
      Section.new("Your editions updated", COLORS[:editions], updated.map(&:summary)),
      Section.new("New editions known", COLORS[:new_editions],
                  new_editions.map { |e| "#{'★ ' if e.details['wanted']}#{e.summary}" }),
      Section.new("Housekeeping", COLORS[:housekeeping],
                  events.map { |e| "#{HOUSEKEEPING_LABELS.fetch(e.origin.to_s, e.origin.to_s.humanize)}: #{e.summary}" })
    ]
  end

  # A section's lines as embeds of at most DESCRIPTION_CHARS, titled with
  # its count and, when it runs on, "(2 of 3)". Empty sections are left out.
  def self.embeds(sections)
    sections.reject { |s| s.lines.empty? }.flat_map do |section|
      chunks = section.lines.map { |l| "• #{l}" }.each_with_object([ [] ]) do |line, out|
        out << [] if out.last.any? && (out.last + [ line ]).join("\n").size > DESCRIPTION_CHARS
        out.last << line
      end
      chunks.each_with_index.map do |chunk, i|
        part = chunks.size > 1 ? " (#{i + 1} of #{chunks.size})" : ""
        { title: "#{section.title} — #{section.lines.size}#{part}", description: chunk.join("\n"), color: section.color }
      end
    end
  end

  def self.notify(title:, sections:)
    Notifications.notify(Notifications::Event.new(kind: :catalogue, level: :info, title:, fields: {},
                                                  url: "#{Rails.application.config.x.public_url}/works", embeds: embeds(sections)))
  end

  def self.mark(events, now)
    CatalogueEvent.where(id: events.map(&:id)).update_all(reported_at: now)
    events.size
  end
end
