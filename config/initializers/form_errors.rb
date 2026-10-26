# Associate model field errors with the shared validation summary.
ActionView::Base.field_error_proc = proc do |html, field|
  fragment = Nokogiri::HTML::DocumentFragment.parse(html)
  if (input = fragment.at_css("input, select, textarea"))
    input["aria-invalid"] = "true"
    input["aria-describedby"] = [ input["aria-describedby"], "#{field.object.model_name.param_key}-errors" ].compact.join(" ")
  end
  fragment.to_html.html_safe
end
