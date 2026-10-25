require "digest"

module Sales
  class Draft
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def self.authorize!(business, actor)
      raise Rejected, "The actor must own this business" unless business.owner_id == actor.id
    end

    def self.lines(raw)
      raise Rejected, "Supply between 1 and 100 product lines" unless raw.is_a?(Array) && raw.size.between?(1, 100)
      lines = raw.filter_map do |line|
        id, quantity = line[:product_id].to_s, line[:quantity].to_s
        next if id.blank? && quantity.blank?
        unless /\A[1-9][0-9]*\z/.match?(id) && id.to_i <= Order::MAX_AMOUNT &&
            /\A[1-9][0-9]*\z/.match?(quantity) && quantity.to_i <= Product::MAX_QUANTITY
          raise Rejected, "Choose a product and a positive whole quantity within the supported limits"
        end
        { product_id: id.to_i, quantity: quantity.to_i }
      end.sort_by { |line| line[:product_id] }
      raise Rejected, "A draft needs at least one product" if lines.empty?
      raise Rejected, "Each product may appear only once; combine duplicate lines" unless lines.map { |line| line[:product_id] }.uniq.size == lines.size
      lines
    end

    def self.products!(business, lines)
      products = business.products.where(id: lines.map { |line| line[:product_id] }).order(:id).lock.to_a
      raise Rejected, "One or more products are unavailable to this business" unless products.size == lines.size
      raise Rejected, "Archived products cannot be sold; edit the draft" if products.any?(&:archived?)
      products
    end

    def self.quote(lines, products)
      products_by_id = products.index_by(&:id)
      quote = lines.map do |line|
        product = products_by_id.fetch(line[:product_id])
        { "product_id" => product.id, "quantity" => line[:quantity], "name" => product.name,
          "sku" => product.sku, "unit_price_minor" => product.price_minor,
          "line_total_minor" => product.price_minor * line[:quantity] }
      end
      total = quote.sum { |line| line.fetch("line_total_minor") }
      raise Rejected, "The sale total exceeds the supported amount" if total > Order::MAX_AMOUNT
      [ quote, total ]
    end

    def self.review!(order, revision, token = nil)
      unless revision.to_s == order.revision.to_s && (token.nil? || token.to_s == order.review_token)
        raise ReviewChanged, "This draft changed after your review. Review its saved items and total again."
      end
    end

    def self.call(business:, actor:, lines:, submission_key: nil, order_id: nil, revision: nil)
      authorize!(business, actor)
      normalized = self.lines(lines)
      digest = Digest::SHA256.hexdigest(normalized.to_json)
      raise Rejected, "Invalid submission identity" if !order_id && !UUID.match?(submission_key.to_s)
      Order.transaction(requires_new: true) do
        if order_id
          order = business.orders.lock.find(order_id)
          raise Rejected, "Only drafts can be edited" unless order.draft?
          review!(order, revision)
        else
          # Serialize creation identities within the business, including retries.
          business.lock!("FOR NO KEY UPDATE")
          submission = business.sale_submissions.find_by(submission_key: submission_key)
          if submission
            raise Rejected, "This submission identity was already used with different items" unless submission.creation_digest == digest
            raise Rejected, "This draft was discarded. Start a new sale to use a new submission identity." unless submission.order_id
            return business.orders.find(submission.order_id)
          end
          order = business.orders.new(submission_key: submission_key, creation_digest: digest)
        end
        products = products!(business, normalized)
        quote, total = quote(normalized, products)
        order.assign_attributes(quote: quote, total_minor: total, review_token: SecureRandom.uuid)
        order.revision += 1 if order.persisted?
        creating = order.new_record?
        order.save!
        business.sale_submissions.create!(submission_key: submission_key, creation_digest: digest, order: order) if creating
        order.order_items.destroy_all
        normalized.each { |line| order.order_items.create!(line.merge(business: business)) }
        order
      end
    end

    def self.discard(business:, actor:, order_id:, revision:)
      authorize!(business, actor)
      Order.transaction(requires_new: true) do
        order = business.orders.lock.find(order_id)
        raise Rejected, "Only drafts can be discarded" unless order.draft?
        review!(order, revision)
        business.sale_submissions.where(order_id: order.id).update_all(order_id: nil)
        order.destroy!
      end
    end
  end
end
