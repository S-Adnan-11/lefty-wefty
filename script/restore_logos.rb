require "json"
require "digest"

database = ActiveRecord::Base.connection_db_config.database
unless ENV["LEFTY_WEFTY_RESTORE_CONFIRM"] == "isolated-target" && database.match?(/\Alefty_wefty_restore_[a-z0-9_]+\z/)
  abort "Restore requires an explicitly confirmed, separate lefty_wefty_restore_* database."
end
abort "Supply the protected logo export directory." unless ARGV.size == 1
target = File.expand_path(ARGV.first)
manifest = JSON.parse(File.read(File.join(target, "manifest.json")))
bucket = ENV.fetch("LEFTY_WEFTY_S3_BUCKET")
unless bucket == ENV["LEFTY_WEFTY_RESTORE_EXPECTED_BUCKET"] && bucket != manifest.fetch("source_bucket")
  abort "Restore requires a separate, explicitly named private bucket."
end
raise "Unsupported export format" unless manifest.fetch("version") == 1
entries = manifest.fetch("objects")
raise "Restore metadata does not match the export" unless entries.map { |entry| entry.fetch("id") }.sort == ActiveStorage::Blob.order(:id).pluck(:id)
entries.each do |entry|
  id = entry.fetch("id")
  raise "Invalid object record" unless id.is_a?(Integer) && id.positive?
  path = File.join(target, "objects", "#{id}.bin")
  blob = ActiveStorage::Blob.find(id)
  unless blob.key == entry.fetch("key") && blob.service_name == "s3" && blob.byte_size == entry.fetch("byte_size") &&
      blob.checksum == entry.fetch("checksum") && File.size(path) == blob.byte_size && Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
    raise "Restore object or database metadata does not match the verified export."
  end
end
entries.each do |entry|
  blob = ActiveStorage::Blob.find(entry.fetch("id"))
  if blob.service.exist?(blob.key)
    raise "Target object differs from the export" unless Digest::SHA256.hexdigest(blob.download) == entry.fetch("sha256")
    next
  end
  File.open(File.join(target, "objects", "#{blob.id}.bin"), "rb") do |file|
    blob.service.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type)
  end
  raise "Restored object verification failed" unless Digest::SHA256.hexdigest(blob.download) == entry.fetch("sha256")
end
puts "Isolated logo restore verified: #{entries.size} objects."
