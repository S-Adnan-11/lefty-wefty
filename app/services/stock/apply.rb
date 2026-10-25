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

        balance = product.quantity + change.quantity.to_i
        raise Rejected, "This change would leave stock below zero" if balance.negative?
        raise Rejected, "This change exceeds the maximum stock quantity" if balance > Product::MAX_QUANTITY

        movement = business.inventory_logs.create!(
          product: product, actor: actor, operation_key: change.operation_key,
          kind: change.kind, quantity_delta: change.quantity.to_i,
          resulting_balance: balance, reason: change.normalized_reason
        )
        # Quantity is readonly on ordinary model saves; all balance writes live here.
        business.products.where(id: product.id).update_all(quantity: balance, updated_at: Time.current)
        movement
      end
    rescue ActiveRecord::RecordNotUnique
      raise Rejected, "This submission was already used for a different stock change"
    end
  end
end
