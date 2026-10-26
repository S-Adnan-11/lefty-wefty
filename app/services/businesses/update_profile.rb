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
          blobs << ActiveStorage::Blob.create_and_upload!(io: upload, filename: "business-logo.#{type.split('/').last}", content_type: type, identify: false)
          blobs << ActiveStorage::Blob.create_and_upload!(io: display, filename: "business-logo.png", content_type: "image/png", identify: false)
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
    ensure
      display&.close!
      blobs&.each { |blob| blob.purge unless blob.attachments.exists? } if $! || business.errors.any?
    end
  end
end
