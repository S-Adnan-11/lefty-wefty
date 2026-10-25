module Stock
  class Apply
    class Rejected < StandardError; end

    def self.call(business:, actor:, product_id:, change:)
      raise Rejected, change.errors.full_messages.to_sentence unless change.valid?
      raise Rejected, "The actor must own this business" unless business.owner_id == actor.id

      product = business.products.find(product_id)
      product.with_lock do
        previous = business.inventory_logs.find_by(operation_key: change.operation_key)
        if previous
          matches = previous.product_id == product.id && previous.actor_id == actor.id &&
            previous.kind == change.kind && previous.quantity_delta == change.quantity.to_i &&
            previous.reason == change.normalized_reason
          raise Rejected, "This submission was already used for a different stock change" unless matches
          return previous
        end

        raise Rejected, "Archived products cannot receive stock or adjustments" if product.archived?
        if change.kind == "opening" && product.inventory_logs.exists?
          raise Rejected, "Opening stock can only be recorded before other movements"
        end

        write!(business: business, actor: actor, product: product, delta: change.quantity.to_i,
          attributes: { operation_key: change.operation_key, kind: change.kind, reason: change.normalized_reason })
      end
    rescue ActiveRecord::RecordNotUnique
      raise Rejected, "This submission was already used for a different stock change"
    end

    # The caller owns the outer sale transaction and locks order, then all
    # products in ascending ID order. Failures deliberately escape to that caller.
    def self.sale!(business:, actor:, product:, item:, reversal: false)
      raise Rejected, "Sale stock writes require an outer transaction" unless Product.connection.transaction_open?
      unless business.owner_id == actor.id && product.business_id == business.id &&
          item.business_id == business.id && item.product_id == product.id
        raise Rejected, "Sale stock references must belong to the owner's business"
      end
      order = business.orders.lock.find(item.order_id)
      expected = reversal ? order.confirmed? : order.draft?
      raise Rejected, "This sale is not in the required state" unless expected
      product.lock!
      raise Rejected, "Archived products cannot be sold" if product.archived? && !reversal
      kind = reversal ? "sale_void" : "sale"
      identity = Digest::SHA256.hexdigest("sale/#{business.id}/#{item.id}/#{kind}").first(32)
      key = [ identity[0, 8], identity[8, 4], identity[12, 4], identity[16, 4], identity[20, 12] ].join("-")
      original = reversal ? item.inventory_logs.find_by!(kind: "sale") : nil
      delta = reversal ? -original.quantity_delta : -item.quantity
      write!(business: business, actor: actor, product: product, delta: delta,
        attributes: { operation_key: key, kind: kind, reason: reversal ? "Recorded sale voided" : "Recorded sale",
          order_item: item, reversal_of: original })
    end

    def self.write!(business:, actor:, product:, delta:, attributes:)
      balance = product.quantity + delta
      raise Rejected, "Insufficient stock: this change would leave stock below zero for #{product.name}" if balance.negative?
      raise Rejected, "This change exceeds the maximum stock quantity" if balance > Product::MAX_QUANTITY
      movement = business.inventory_logs.create!(attributes.merge(product: product, actor: actor,
        quantity_delta: delta, resulting_balance: balance))
      # Quantity is readonly on ordinary model saves; all balance writes live here.
      business.products.where(id: product.id).update_all(quantity: balance, updated_at: Time.current)
      movement
    end
    private_class_method :write!
  end
end
