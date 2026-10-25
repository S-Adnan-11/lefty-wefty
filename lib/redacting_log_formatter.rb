# Reset links carry credentials in a path segment, outside parameter filtering.
class RedactingLogFormatter < ActiveSupport::Logger::SimpleFormatter
  def call(severity, time, progname, message)
    super.gsub(%r{(/passwords/)[^/?\s"'<>]+}, '\1[FILTERED]')
  end
end
