require "fileutils"

abort "Disposable GitHub CI only." unless ENV["GITHUB_ACTIONS"] == "true" && ENV["RUNNER_TEMP"]
source = File.join(ENV.fetch("RUNNER_TEMP"), "lefty-wefty-object-source")
image = File.join(ENV.fetch("RUNNER_TEMP"), "lefty-wefty-object-image")
raise "Expected new CI fixture directories" if File.exist?(source) || File.exist?(image)
FileUtils.mkdir_p([ source, image ])
def command!(*arguments, **options)
  raise "Cannot build the pinned S3-compatible CI fixture" unless system(*arguments, **options)
end
command!("git", "init", source)
command!("git", "-C", source, "remote", "add", "origin", "https://github.com/minio/minio.git")
# Immutable official annotated tag for RELEASE.2025-09-07T16-13-09Z.
command!("git", "-C", source, "fetch", "--depth", "1", "origin", "01ce918d8279a20e4706b96a64396146894adee4")
command!("git", "-C", source, "checkout", "--detach", "FETCH_HEAD")
command!({ "CGO_ENABLED" => "0", "GOTOOLCHAIN" => "auto" }, "go", "build", "-trimpath", "-ldflags=-s -w", "-o", File.join(image, "minio"), ".", chdir: source)
File.write(File.join(image, "Dockerfile"), <<~DOCKERFILE)
  FROM ruby:3.4.12-slim-bookworm@sha256:549e18ddab0acedc09a63be26cc3bdb6c05988bf3ebccfd34fbc90869395097c
  COPY minio /usr/local/bin/minio
  ENV MINIO_UPDATE=off MINIO_BROWSER=off
  ENTRYPOINT ["/usr/local/bin/minio"]
DOCKERFILE
command!("docker", "build", "--tag", "lefty-wefty-ci-objects", image)
puts "S3-compatible fixture built from pinned public source."
