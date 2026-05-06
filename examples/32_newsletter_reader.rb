#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 32: Newsletter Reader
#
# Downloads the latest RoboRuby (Ruby AI News) newsletter via RSS and uses
# a robot to extract key stories, gems, and highlights from the issue.
#
# Demonstrates:
#   - Custom tool that fetches live data from the web
#   - Robot reasoning over real-world structured content
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/32_newsletter_reader.rb

require "net/http"
require "open3"
require "uri"
require "rexml/document"
require "rexml/xpath"

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"
require "logger"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

NEWSLETTER_RSS_URL = "https://rss.beehiiv.com/feeds/MTJunJRFxo.xml"

class FetchLatestNewsletter < RubyLLM::Tool
  description "Fetches the latest issue of the RoboRuby Ruby AI newsletter via RSS. " \
              "Returns the issue title, publication date, web URL, and full article text."

  def execute
    uri      = URI(NEWSLETTER_RSS_URL)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.get(uri.request_uri) }

    raise "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    doc  = REXML::Document.new(response.body)
    item = REXML::XPath.first(doc, "//channel/item")
    return "No issues found in the newsletter RSS feed." unless item

    ns = { "content" => "http://purl.org/rss/1.0/modules/content/" }

    title    = text_of(item, "title")
    pub_date = text_of(item, "pubDate")
    url      = text_of(item, "link")
    html     = REXML::XPath.first(item, "content:encoded", ns)&.text ||
               text_of(item, "description") || ""

    plain = html_to_markdown(html)

    <<~TEXT
      Issue: #{title}
      Published: #{pub_date}
      URL: #{url}

      #{plain[0, 20_000]}
    TEXT
  end

  private

  def text_of(node, xpath)
    REXML::XPath.first(node, xpath)&.text&.strip
  end

  def html_to_markdown(html)
    md, = Open3.capture3(
      "html2markdown --domain=https://rubyai.beehiiv.com",
      stdin_data: html
    )
    md.gsub(/\]\(([^)]+)\)/) { "](#{strip_utm($1)})" }
  end

  def strip_utm(url)
    return url unless url.include?("?")
    base, query = url.split("?", 2)
    kept = query.split("&").reject { |p| p.start_with?("utm_") }
    kept.empty? ? base : "#{base}?#{kept.join("&")}"
  end
end

puts "=" * 60
puts "Example 32: Newsletter Reader"
puts "=" * 60
puts

robot = RobotLab.build(
  name: "newsletter_analyst",
  system_prompt: <<~PROMPT,
    You are a sharp technical editor summarizing the RoboRuby Ruby AI newsletter
    for busy developers. When given newsletter content, extract and present:

    1. **Headline story** — the biggest news in Ruby/AI this issue.
    2. **Notable gems or tools** — new or updated libraries worth knowing about.
    3. **Key articles or tutorials** — important reads linked in the issue.
    4. **Quick takes** — 3-5 bullets on other interesting items.

    The content includes Markdown links in [text](url) format. You MUST preserve
    these links in your output — every article title, gem name, and tool mentioned
    should be a clickable Markdown link using the URL from the source content.

    Use the FetchLatestNewsletter tool to get the content, then give your summary.
    Be concise and opinionated — developers are busy.

    Before deciding what to include, use the recall_knowledge tool to check past preferences.
    After a discussion or decision reveals something worth remembering, use the record_knowledge tool.
    When uncertain whether to include something and no past knowledge applies, skip it.
  PROMPT
  local_tools: [FetchLatestNewsletter],
  model: "claude-haiku-4-5-20251001",
  learn: true,
  learn_domain: "newsletter curation"
)

puts "Fetching and summarizing the latest RoboRuby newsletter..."
puts "-" * 60
puts

result = robot.run("Fetch the latest newsletter and give me your summary.")

puts result.reply
puts
puts "-" * 60
puts "Done."
