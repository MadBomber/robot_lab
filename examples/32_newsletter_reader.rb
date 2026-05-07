#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 32: Newsletter Issue Retriever
#
# Fetches all unprocessed issues of the RoboRuby (Ruby AI News) newsletter
# via RSS and saves each as a Markdown file in the Obsidian Clippings folder.
#
# - Processes oldest unprocessed issue first
# - Filename: <newsletter-name>_YYYYMMDD.md
# - Includes YAML frontmatter with source URL (compatible with Clippings workflow)
# - Tracks processed issue URLs in ~/.robot_lab/newsletter_processed.yaml
#
# Usage:
#   ruby examples/32_newsletter_reader.rb

require "net/http"
require "open3"
require "time"
require "uri"
require "yaml"
require "fileutils"
require "rexml/document"
require "rexml/xpath"

NEWSLETTER_RSS_URL   = "https://rss.beehiiv.com/feeds/MTJunJRFxo.xml"
CLIPPINGS_DIR        = File.expand_path("/Users/dewayne/Documents/obsidian_order_intelligence/PKM/Clippings")
PROCESSED_STATE_FILE = File.join(Dir.home, ".robot_lab", "newsletter_processed.yaml")

# Tracks which newsletter issue URLs have been saved.
class ProcessedIssues
  def initialize(path: PROCESSED_STATE_FILE)
    @path = path
    @urls = load_urls
  end

  def processed?(url)
    @urls.include?(url)
  end

  def mark_processed(url)
    @urls << url
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, YAML.dump(@urls.uniq))
  end

  def count = @urls.size

  private

  def load_urls
    return [] unless File.exist?(@path)
    Array(YAML.safe_load(File.read(@path)) || [])
  end
end

# Fetches the RSS feed and returns all items sorted oldest-first.
# Each item: { title:, url:, pub_date:, published_at:, html: }
def fetch_rss_items
  uri      = URI(NEWSLETTER_RSS_URL)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.get(uri.request_uri) }
  raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

  doc  = REXML::Document.new(response.body)
  ns   = { "content" => "http://purl.org/rss/1.0/modules/content/" }

  # Derive a safe newsletter name from the channel title once
  channel_title = REXML::XPath.first(doc, "//channel/title")&.text&.strip || "newsletter"

  items = REXML::XPath.match(doc, "//channel/item")
  items.filter_map do |item|
    url      = REXML::XPath.first(item, "link")&.text&.strip
    title    = REXML::XPath.first(item, "title")&.text&.strip
    pub_date = REXML::XPath.first(item, "pubDate")&.text&.strip
    html     = REXML::XPath.first(item, "content:encoded", ns)&.text ||
               REXML::XPath.first(item, "description")&.text || ""

    next unless url && title && pub_date

    {
      title:        title,
      url:          url,
      pub_date:     pub_date,
      published_at: Time.parse(pub_date),
      html:         html,
      channel_name: channel_title
    }
  end.sort_by { |item| item[:published_at] }
end

# Converts HTML to Markdown via html2markdown CLI, stripping UTM params.
def html_to_markdown(html)
  md, = Open3.capture3(
    "html2markdown --domain=https://rubyai.beehiiv.com",
    stdin_data: html
  )
  md.gsub(/\]\(([^)]+)\)/) do
    url = $1
    if url.include?("?")
      base, query = url.split("?", 2)
      kept = query.split("&").reject { |p| p.start_with?("utm_") }
      "](#{kept.empty? ? base : "#{base}?#{kept.join("&")}"})"
    else
      "](#{url})"
    end
  end
end

# Builds the output filename: <newsletter-name>_YYYYMMDD.md
def output_filename(channel_name, published_at)
  safe_name = channel_name.downcase.gsub(/[^a-z0-9]+/, "_").delete_suffix("_")
  date_str  = published_at.strftime("%Y%m%d")
  "#{safe_name}_#{date_str}.md"
end

# Wraps markdown content in YAML frontmatter compatible with the Clippings workflow.
def wrap_with_frontmatter(title:, url:, pub_date:, body:)
  date = Time.parse(pub_date).strftime("%Y-%m-%d")
  <<~MD
    ---
    source: #{url}
    title: "#{title.gsub('"', '\\"')}"
    date: #{date}
    ---

    # #{title}

    #{body.strip}
  MD
end

# ── Main ──────────────────────────────────────────────────────────────────────

puts "=" * 60
puts "Example 32: Newsletter Issue Retriever"
puts "=" * 60
puts

FileUtils.mkdir_p(CLIPPINGS_DIR)
state = ProcessedIssues.new

print "Fetching RSS feed... "
all_items = fetch_rss_items
pending   = all_items.reject { |item| state.processed?(item[:url]) }
puts "#{all_items.size} total issues found."

if pending.empty?
  puts "All issues already saved. Nothing to do."
  exit
end

puts "#{pending.size} unprocessed (#{state.count} already done). Saving oldest-first."
puts

pending.each_with_index do |item, idx|
  filename = output_filename(item[:channel_name], item[:published_at])
  filepath = File.join(CLIPPINGS_DIR, filename)

  print "[#{idx + 1}/#{pending.size}] #{item[:title]} (#{item[:published_at].strftime("%Y-%m-%d")})... "

  body     = html_to_markdown(item[:html])
  content  = wrap_with_frontmatter(
    title:    item[:title],
    url:      item[:url],
    pub_date: item[:pub_date],
    body:     body
  )

  File.write(filepath, content)
  state.mark_processed(item[:url])

  puts "saved → #{filename}"
end

puts
puts "Done. #{pending.size} issue(s) saved to #{CLIPPINGS_DIR}"
