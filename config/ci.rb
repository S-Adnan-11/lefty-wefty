# Run using ruby bin/ci.
CI.run do
  step "Style: Ruby", "ruby bin/rubocop"
  step "Security: Gems", "ruby bin/bundler-audit check --update"
  step "Security: Code", "ruby bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "ruby bin/rails test"
  step "Autoloading", "ruby bin/rails zeitwerk:check"
end
