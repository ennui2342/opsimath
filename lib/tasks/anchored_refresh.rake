namespace :anchored_refresh do
  # docs/CATALOG.md "Anchored editions", step 3 — what a refresh would do.
  desc "Dry run: anchors, and per-field actions, with examples"
  task plan: :environment do
    plans = AnchoredRefresh.plan
    puts "editions: #{plans.size}"
    plans.group_by(&:anchor_status).sort_by { |_, ps| -ps.size }.each do |status, ps|
      by = ps.filter_map { |p| p.anchor&.provider }.tally
      puts "  #{status}: #{ps.size} #{by.presence&.inspect}"
    end
    fields = plans.flat_map(&:fields)
    puts "fields:"
    fields.group_by(&:field).each do |field, fs|
      counts = fs.map(&:action).tally.except(:same)
      puts "  #{field.to_s.ljust(13)} #{counts.sort.to_h}" if counts.any?
    end
    secondary = plans.flat_map(&:secondary)
    puts "secondary fills: #{secondary.map(&:field).tally}"
    puts "editions with any change: #{plans.count { |p| p.fields.any? { |f| f.action != :same && f.action != :anchor_blank && f.action != :manual } || p.secondary.any? }}"
    n = ENV.fetch("EXAMPLES", 4).to_i
    %i[update replace manual fill].each do |action|
      puts "-- #{action}"
      plans.flat_map { |p| p.fields.select { |f| f.action == action }.map { |f| [ p, f ] } }
           .group_by { |_, f| f.field }.each do |field, pairs|
        pairs.first(n).each { |p, f| puts "   #{field}: #{p.work&.title.to_s.truncate(30)} — #{f.current.inspect} (#{f.source || '?'}) -> #{f.proposed.inspect}" }
      end
    end
  end
end
