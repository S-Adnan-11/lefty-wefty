module Businesses
  class UpdateProfile
    def self.call(business:, actor:, name:, upload: nil, remove_logo: false)
      raise ActiveRecord::RecordNotFound unless business.owner_id == actor.id
      blobs = []
      display = nil
      business.with_lock do
        business.name = name
        return false unless business.valid?
        if upload.present? && remove_logo
          business.errors.add(:logo, "choose either a replacement or removal")
          return false
        end
        if upload.present?
          display, type = LogoImage.prepare(upload)
          upload.rewind
          store_blob(blobs, io: upload, filename: "business-logo.#{type.split('/').last}", content_type: type)
          store_blob(blobs, io: display, filename: "business-logo.png", content_type: "image/png")
          business.logo = blobs.first
          business.logo_display = blobs.last
        elsif remove_logo
          business.logo = nil
          business.logo_display = nil
        end
        business.save!
      end
      true
    rescue LogoImage::Invalid => error
      business.errors.add(:logo, error.message)
      false
    rescue StandardError => error
      raise unless storage_error?(error)
      business.errors.add(:logo, "storage is temporarily unavailable. Try again.")
      false
    ensure
      display&.close!
      if $! || business.errors.any?
        blobs&.each do |blob|
          next if blob.attachments.exists?
          begin
            blob.service.delete(blob.key)
            blob.destroy! if blob.persisted?
          rescue StandardError
            Rails.logger.warn("Unattached logo cleanup needs a storage retry.")
          end
        end
      end
    end

    def self.storage_error?(error)
      (defined?(Aws::S3::Errors::ServiceError) && error.is_a?(Aws::S3::Errors::ServiceError)) ||
        (defined?(Seahorse::Client::NetworkingError) && error.is_a?(Seahorse::Client::NetworkingError))
    end

    def self.store_blob(blobs, io:, filename:, content_type:)
      blob = ActiveStorage::Blob.create_after_unfurling!(io: io, filename: filename, content_type: content_type, identify: false)
      # Keep its key available for cleanup even when an upload fails.
      blobs << blob
      blob.upload_without_unfurling(io)
    end
  end
end
