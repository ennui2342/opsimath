# A book linked to several ISFDB titles (170 were, 2026-11-13) — mostly by
# an ISBN lookup that landed on something the book contains or is
# contained in (The Midwich Cuckoos' ISBN was also a schools chapbook's).
# Isfdb::MainTitles.ordered already picks the title that is the book; this
# drops the others whose main title is a different work, leaving a
# rejected link (`isfdb_title_rejected`) so KnownEditionsRefresh doesn't
# put them back. Links to another form of the kept title (a variant: the
# same main title) stay — their printings are the book's too. A book on
# a suspect link is left for Mark (TitleCleanup's "Wrong ISFDB link?").
# `plan` is a dry run.
class TitleLinkPrune
  REJECTED = "isfdb_title_rejected".freeze
  Prune = Struct.new(:work, :keep, :drop, keyword_init: true) # keep: record; drop: [[value, record]]

  def self.plan(...) = new(...).plan

  def self.apply(...) = new(...).apply

  def initialize(client: Isfdb::Client.new)
    @client = client
  end

  def plan
    @plan ||= begin
      multi = WorkIdentifier.where(id_type: "isfdb_title").group(:work_id).having("count(*) > 1").pluck(:work_id)
      links = WorkIdentifier.where(id_type: "isfdb_title", work_id: multi).order(:id).pluck(:work_id, :value).group_by(&:first)
      Work.where(id: multi).filter_map do |work|
        next if TitleCleanup.suspect?(work)

        records = links[work.id].map(&:last).filter_map { |v| (r = @client.title(v)) && [ v, r ] }
        next if records.size < 2

        keep = Isfdb::MainTitles.ordered(records.map(&:last), work.title, own: own_titles(work, records.map(&:first))).first
        drop = records.reject { |_, r| r.dig("main", "id").to_s == keep.dig("main", "id").to_s }
        Prune.new(work:, keep:, drop:) if drop.any?
      end
    end
  end

  # -> links dropped
  def apply
    plan.sum do |p|
      WorkIdentifier.transaction do
        p.drop.each do |value, _|
          p.work.work_identifiers.where(id_type: "isfdb_title", value:).delete_all
          p.work.work_identifiers.find_or_create_by!(id_type: REJECTED, value:) { |i| i.source = "title_link_prune" }
        end
      end
      p.drop.size
    end
  end

  private

  # Which of the book's linked titles hold a printing of one of its editions.
  def own_titles(work, values)
    pubs = EditionIdentifier.where(id_type: "isfdb", edition_id: work.editions.select(:id)).pluck(:value).to_set
    return [] if pubs.empty?

    values.select { |v| @client.title_editions(v).any? { |ed| pubs.include?(ed["_isfdb_pub_id"].to_s) } }
  end
end
