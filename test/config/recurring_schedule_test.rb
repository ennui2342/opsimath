require "test_helper"
require "fugit"

# The nightly jobs (config/recurring.yml) run on UK time and start well
# before the cluster's 05:10-05:55 maintenance window (node reboots), in
# summer as in winter — the pods' clock is UTC (tm 15f1e314).
class RecurringScheduleTest < ActiveSupport::TestCase
  test "every nightly job is on UK time and starts before 05:00 UK time, in GMT and BST" do
    tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    daily = tasks.select { |_, task| task["schedule"].to_s.start_with?("every day") }
    assert_not_empty daily

    daily.each do |key, task|
      assert task["schedule"].end_with?("Europe/London"), "#{key}: “#{task['schedule']}” has no UK time zone"
      cron = Fugit.parse(task["schedule"])
      [ Time.utc(2027, 1, 15), Time.utc(2027, 7, 15) ].each do |day|
        uk = cron.next_time(day).to_t.in_time_zone("Europe/London").strftime("%H:%M")
        assert_operator uk, :<, "05:00", "#{key} starts at #{uk} UK time on #{day.to_date}: too near the 05:10 maintenance window"
      end
    end
  end
end
