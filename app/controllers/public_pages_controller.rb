class PublicPagesController < ApplicationController
  allow_unauthenticated_access

  def robots
    rules = "User-agent: *\nAllow: /\n"
    rules += "Sitemap: #{PublicSite.url('/sitemap.xml')}\n" if PublicSite.indexing?
    render plain: rules
  end

  def sitemap
    return head :not_found unless PublicSite.indexing?

    render xml: %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>#{ERB::Util.html_escape(PublicSite.url)}</loc></url></urlset>)
  end
end
