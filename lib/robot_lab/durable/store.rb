# frozen_string_literal: true

require "yaml"
require "fileutils"

module RobotLab
  module Durable
    class Store
      DEFAULT_PATH = File.join(Dir.home, ".robot_lab", "durable")

      MIN_WORD_LENGTH = 3

      def initialize(path: DEFAULT_PATH)
        @path = path
        FileUtils.mkdir_p(@path)
      end

      # Return entries matching query keywords, sorted by descending confidence.
      #
      # @param query [String] natural-language search string
      # @param domain [String, nil] restrict to one domain file; nil searches all
      # @param min_confidence [Float] exclude entries below this threshold
      # @return [Array<Entry>]
      def recall(query:, domain: nil, min_confidence: 0.0)
        entries = domain ? load_domain(domain) : load_all
        words   = tokenize(query)

        entries
          .select { |e| e.confidence >= min_confidence }
          .select { |e| matches?(e, words) }
          .sort_by { |e| -e.confidence }
      end

      # Persist a new entry. If an entry with the same content already exists
      # in the domain file, increment its confidence and use_count instead.
      #
      # @param entry [Entry]
      # @return [Entry] the stored entry (may differ if an existing one was updated)
      def record(entry)
        with_domain_lock(entry.domain) do
          entries = load_domain(entry.domain)
          idx     = entries.find_index { |e| e.content.downcase == entry.content.downcase }

          if idx
            entries[idx] = entries[idx].confirm
          else
            entries << entry
          end

          save_domain(entry.domain, entries)
          entries[idx || -1]
        end
      end

      # Increment confidence and use_count on a stored entry.
      #
      # @param entry [Entry]
      # @return [Entry] the updated entry
      def confirm(entry)
        updated = entry.confirm
        record_exact(updated)
        updated
      end

      private

      def matches?(entry, words)
        text = "#{entry.content} #{entry.domain}".downcase
        words.any? { |w| text.include?(w) }
      end

      def tokenize(str)
        str.downcase.split(/\s+/).reject { |w| w.length < MIN_WORD_LENGTH }
      end

      def load_domain(domain)
        file = domain_file(domain)
        return [] unless File.exist?(file)

        raw = Array(YAML.safe_load(File.read(file)) || [])
        raw.map { |h| Entry.from_h(h) }
      end

      def load_all
        Dir.glob(File.join(@path, "*.yaml")).flat_map do |file|
          raw = Array(YAML.safe_load(File.read(file)) || [])
          raw.map { |h| Entry.from_h(h) }
        end
      end

      def save_domain(domain, entries)
        File.write(domain_file(domain), YAML.dump(entries.map(&:to_h)))
      end

      # Replace a specific entry by exact content match (used by confirm).
      def record_exact(entry)
        with_domain_lock(entry.domain) do
          entries = load_domain(entry.domain)
          idx     = entries.find_index { |e| e.content.downcase == entry.content.downcase }
          raise RobotLab::Error, "Cannot confirm: entry not found in domain '#{entry.domain}'" unless idx
          entries[idx] = entry
          save_domain(entry.domain, entries)
        end
      end

      def domain_file(domain)
        safe = domain.to_s.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
        File.join(@path, "#{safe}.yaml")
      end

      def with_domain_lock(domain, &block)
        lock_path = domain_file(domain) + ".lock"
        File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |f|
          f.flock(File::LOCK_EX)
          block.call
        end
      end
    end
  end
end
