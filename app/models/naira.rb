class Naira
  class Invalid < ArgumentError; end

  def self.parse(value)
    text = value.to_s.strip
    unless text.bytesize <= 32 && /\A(?:[0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?\z/.match?(text)
      raise Invalid, "must be a naira amount such as 1250 or 1,250.50, with at most two decimal places"
    end
    whole, fraction = text.delete(",").split(".", 2)
    minor = whole.to_i * 100 + fraction.to_s.ljust(2, "0").to_i
    unless minor.between?(1, Product::MAX_PRICE_MINOR)
      raise Invalid, "must be between ₦0.01 and ₦9,999,999,999.99"
    end
    minor
  end

  def self.format(minor)
    return "" if minor.nil?
    "#{minor / 100}.#{Kernel.format('%02d', minor % 100)}"
  end
end
