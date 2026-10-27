require "json"
require "digest"
require "base64"
require "fileutils"

abort "Pause application writes and confirm LEFTY_WEFTY_BACKUP_CONFIRMED_MAINTENANCE=true." unless ENV["LEFTY_WEFTY_BACKUP_CONFIRMED_MAINTENANCE"] == "true"
abort "Supply a new protected export directory." unless ARGV.size == 1
target = File.expand_path(ARGV.first)
if Pathname.new(target).ascend.any? { |path| path.join(".git").exist? } || target.start_with?(Rails.root.to_s + File::SEPARATOR)
  abort "Exports must stay outside Git worktrees."
end
abort "Export target already exists." if File.exist?(target)
previous_mask = File.umask(0o077)
begin
  FileUtils.mkdir_p(File.join(target, "objects"), mode: 0o700)
  manifest = { version: 1, exported_at: Time.now.utc.iso8601, source_bucket: ENV["LEFTY_WEFTY_S3_BUCKET"], objects: [] }
  ActiveStorage::Blob.order(:id).find_each do |blob|
    digest = Digest::SHA256.new
    md5 = Digest::MD5.new
    bytes = 0
    File.open(File.join(target, "objects", "#{blob.id}.bin"), "wb", 0o600) do |file|
      blob.download do |chunk|
        file.write(chunk)
        digest.update(chunk)
        md5.update(chunk)
        bytes += chunk.bytesize
      end
    end
    unless bytes == blob.byte_size && Base64.strict_encode64(md5.digest) == blob.checksum
      raise "An exported object does not match its database metadata."
    end
    manifest[:objects] << { id: blob.id, key: blob.key, service_name: blob.service_name, byte_size: bytes, checksum: blob.checksum, sha256: digest.hexdigest }
  end
  File.write(File.join(target, "manifest.json"), JSON.pretty_generate(manifest), perm: 0o600)
  puts "Logo export verified: #{manifest[:objects].size} objects."
ensure
  File.umask(previous_mask)
end
