require "test_helper"

class NairaTest < ActiveSupport::TestCase
  test "naira strings convert exactly once without floating point" do
    { "1250" => 125000, "1250.5" => 125050, "1,250.50" => 125050, "  0.01 \t" => 1,
      "9,999,999,999.99" => Product::MAX_PRICE_MINOR, "001.20" => 120 }.each do |input, expected|
      assert_equal expected, Naira.parse(input), input
    end
    [ "", "0", "0.00", "-1", "+1", "1e3", "1.001", ".50", "1.", "1,25.00", "1,250,00",
      "01,250", "1 250", "1,250.5.0", "₦100", "10000000000", "9" * 200, "NaN", "1\n2" ].each do |input|
      assert_raises(Naira::Invalid, input) { Naira.parse(input) }
    end
  end
end
