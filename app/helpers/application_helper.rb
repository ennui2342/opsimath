module ApplicationHelper
  # A book's statuses (Work#statuses) as badges — the Books list, the book
  # page, and the author / series / publisher pages.
  WORK_STATUS_BADGES = { owned: [ "Owned", :success ], wanted: [ "Wanted", :default ], reading: [ "Reading", :accent ],
                         read: [ "Read", :info ], dnf: [ "DNF", :default ] }.freeze

  SOURCE_LABELS = { "isfdb" => "ISFDB", "openlibrary" => "Open Library", "goodreads" => "Goodreads" }.freeze

  # One line for a queued decision on the book page: "ISFDB's record
  # differs on publisher, language, page count and cover."
  def decision_summary(decision)
    source = SOURCE_LABELS.fetch(decision.payload["source"].to_s, decision.payload["source"].to_s.humanize.presence || "A provider")
    fields = Array(decision.payload["fields"]).map { |f| f == "cover_image" ? "cover" : f.humanize(capitalize: false) }
    case decision.kind
    when "enrichment_conflict"
      if decision.payload["identity_question"]
        "#{source}'s record looks like a different printing: #{decision.payload['identity_question']}."
      else
        "#{source}'s record differs on #{fields.to_sentence.presence || 'some details'}."
      end
    when "edition_reconciliation" then "#{source} lists a different edition of this book."
    else "A decision about this edition is waiting."
    end
  end

  # Cover artists' names, each linked to their page ("A, B" credits split).
  def artist_links(names, **link_options)
    names = Array(names).flat_map { |n| n.to_s.split(", ") }.map(&:strip).compact_blank
    safe_join(names.map { |n| link_to(n, artist_path(name: n), class: "hover:underline", **link_options) }, ", ")
  end

  # Where the review screen's actions go: the queue (optionally one kind),
  # or back to the book page it was opened from.
  def decision_params(kind_filter) = { kind: kind_filter, work_id: params[:work_id] }.compact

  # Marks every find card on one cover of one book, so "Not this cover"
  # can remove them all at once.
  def find_cover_class(want, cover_id) = "find-cover-#{want.id}-#{cover_id}"

  # The small action on a book card — Want it, Add, Want this cover — one
  # box for a link and a button alike, so they line up
  # (docs/DESIGN_SYSTEM.md, "Book cards").
  def card_button_class
    "inline-flex h-6 items-center rounded bg-gray-200 px-2 text-xs font-medium text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
  end

  # A book's title, linked to its page — wherever a title is shown (Mark,
  # 2026-11-09). `classes` add to the hover underline.
  def work_link(work, text = work.title, classes: nil)
    link_to text, work_path(work), class: [ "hover:underline", classes ].compact.join(" ")
  end

  # Several books' titles (an omnibus edition's), each linked.
  def work_links(works, fallback:) = works.any? ? safe_join(works.map { |w| work_link(w) }, ", ") : fallback
end
