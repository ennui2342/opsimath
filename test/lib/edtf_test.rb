require "test_helper"

class EdtfTest < ActiveSupport::TestCase
  test "keeps only the precision the text gives" do
    {
      "1964" => "1964", "April 1996" => "1996-04", "Sep 16, 1990" => "1990-09-16",
      "February 2, 1998" => "1998-02-02", "16 September 1990" => "1990-09-16", "cop. 2021" => "2021",
      "1978-04" => "1978-04", "2003-12-01" => "2003-12-01", "Oct. 2005" => "2005-10"
    }.each { |text, edtf| assert_equal edtf, Edtf.from_text(text), text }
  end

  test "no plausible year is nil" do
    [ nil, "", "n.d.", "unknown", "123" ].each { |text| assert_nil Edtf.from_text(text), text.inspect }
  end
end
