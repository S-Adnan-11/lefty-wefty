module Businesses
  class LogoImage
    class Invalid < StandardError; end
    TYPES = { "PNG" => "image/png", "JPEG" => "image/jpeg", "WEBP" => "image/webp" }.freeze

    def self.prepare(upload)
      unless upload.is_a?(ActionDispatch::Http::UploadedFile)
        raise Invalid, "Choose a PNG, JPEG or WebP image from your device."
      end
      raise Invalid, "Choose a logo no larger than 2 MB." if upload.size > 2.megabytes
      header = File.binread(upload.path, 12)
      format = if header.start_with?("\x89PNG\r\n\x1a\n".b)
        "PNG"
      elsif header.start_with?("\xff\xd8\xff".b)
        "JPEG"
      elsif header.start_with?("RIFF") && header.byteslice(8, 4) == "WEBP"
        "WEBP"
      end
      unless format && upload.content_type == TYPES.fetch(format)
        raise Invalid, "Choose a PNG, JPEG or WebP file whose image type matches its contents."
      end
      # Explicit decoder, restricted policy, no user-controlled command arguments.
      dimensions = MiniMagick.identify do |command|
        command << "-regard-warnings" << "-format" << "%w %h %n" << "#{format}:#{upload.path}"
      end.split.map(&:to_i)
      width, height, frames = dimensions
      unless frames == 1 && width.positive? && height.positive? && width <= 4096 && height <= 4096 && width * height <= 8_000_000
        raise Invalid, "Choose a still image up to 4096 pixels per side and 8 million pixels in total."
      end
      output = Tempfile.new([ "logo-display", ".png" ], binmode: true)
      MiniMagick.convert do |command|
        command << "-regard-warnings" << "#{format}:#{upload.path}" << "-auto-orient" << "-strip" << "-resize" << "512x512>" << "PNG:#{output.path}"
      end
      output.rewind
      [ output, TYPES.fetch(format) ]
    rescue MiniMagick::Error
      output&.close!
      raise Invalid, "This logo could not be read. Choose a valid still PNG, JPEG or WebP image within the size limits."
    end
  end
end
