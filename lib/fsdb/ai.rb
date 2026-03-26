# frozen_string_literal: true

require "faraday"
require "json"

module Fsdb
  module Ai
    ANTHROPIC_URL    = "https://api.anthropic.com/v1/messages"
    DEFAULT_OLLAMA_URL   = "http://pmacs-dev-142.local:11434"
    DEFAULT_OLLAMA_MODEL = "gemma3:1b"
    FAILURE_LIMIT = 3

    @mutex             = Mutex.new
    @consecutive_fails = 0
    @circuit_open      = false

    class << self
      # Batch: send many directories in one prompt.
      # candidates: [{path:, children:}, ...]
      # Returns: {path => [categories]}
      def suggest_categories_batch(candidates, existing_categories, max: 3)
        return {} if candidates.empty?

        if @mutex.synchronize { @circuit_open }
          log "circuit breaker open — skipping batch of #{candidates.size} dirs"
          return {}
        end

        provider = ENV.fetch("FSDB_AI_PROVIDER", "ollama")
        result   = dispatch_batch(provider, candidates, existing_categories, max)
        @mutex.synchronize { reset_failures }
        result
      rescue Faraday::Error, JSON::ParserError, StandardError => e
        @mutex.synchronize { record_failure("batch(#{candidates.size})", e) }
        {}
      end

      def suggest_categories(dir_path, child_names, existing_categories, max: 3)
        if @mutex.synchronize { @circuit_open }
          log "circuit breaker open — skipping AI for #{dir_path}"
          return []
        end

        provider = ENV.fetch("FSDB_AI_PROVIDER", "ollama")
        result   = dispatch(provider, dir_path, child_names, existing_categories, max)
        @mutex.synchronize { reset_failures }
        result
      rescue Faraday::Error, JSON::ParserError, StandardError => e
        @mutex.synchronize { record_failure(dir_path, e) }
        []
      end

      # Allow tests to reset state between runs.
      def reset!
        @mutex.synchronize { @consecutive_fails = 0; @circuit_open = false }
      end

      private

      def dispatch_batch(provider, candidates, existing, max)
        case provider
        when "ollama"    then batch_via_ollama(candidates, existing, max)
        when "anthropic" then batch_via_anthropic(candidates, existing, max)
        else
          log "unknown FSDB_AI_PROVIDER '#{provider}' — skipping"
          {}
        end
      end

      def batch_via_ollama(candidates, existing, max)
        base_url = ENV.fetch("FSDB_OLLAMA_URL", DEFAULT_OLLAMA_URL)
        model    = ENV.fetch("FSDB_OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL)
        prompt   = build_batch_prompt(candidates, existing, max)

        log "ollama #{model} — batch of #{candidates.size} dirs"

        conn = Faraday.new(url: base_url) do |f|
          f.request :json
          f.response :raise_error
        end

        response = conn.post("/api/chat") do |req|
          req.body = { model:, stream: false, messages: [{ role: "user", content: prompt }] }
        end

        body = JSON.parse(response.body)
        text = body.dig("message", "content").to_s.strip
        result = parse_batch_response(text, candidates)
        log "  → #{result.transform_values { |v| v }.inspect}"
        result
      end

      def batch_via_anthropic(candidates, existing, max)
        api_key = ENV["ANTHROPIC_API_KEY"]
        unless api_key
          log "ANTHROPIC_API_KEY not set — skipping"
          return {}
        end

        model  = ENV.fetch("FSDB_AI_MODEL", "claude-opus-4-5")
        prompt = build_batch_prompt(candidates, existing, max)

        log "anthropic #{model} — batch of #{candidates.size} dirs"

        conn = Faraday.new(url: ANTHROPIC_URL) do |f|
          f.request :json
          f.response :raise_error
        end

        response = conn.post do |req|
          req.headers["x-api-key"]         = api_key
          req.headers["anthropic-version"] = "2023-06-01"
          req.body = { model:, max_tokens: 1024, messages: [{ role: "user", content: prompt }] }
        end

        body = JSON.parse(response.body)
        text = body.dig("content", 0, "text").to_s.strip
        result = parse_batch_response(text, candidates)
        log "  → #{result.inspect}"
        result
      end

      def build_batch_prompt(candidates, existing, max)
        hint = existing.any? ? "Existing categories (prefer reusing): #{existing.first(20).join(", ")}.\n" : ""

        dirs_block = candidates.each_with_index.map do |c, i|
          sample = c[:children].first(20).join(", ")
          "#{i + 1}. #{c[:path]}\n   Contents: #{sample}"
        end.join("\n")

        <<~PROMPT
          You are cataloguing a filesystem for personal use.
          #{hint}
          For each directory below, suggest up to #{max} short topic category labels describing its human-interest subject.
          Good examples: "python programming", "music", "tax documents", "machine learning", "social skills".
          Avoid generic terms like "files" or "folder". Skip directories that clearly have no meaningful topic.

          Directories:
          #{dirs_block}

          Reply with ONLY a JSON object mapping each full directory path to an array of category strings:
          {
            "/path/to/dir": ["category one", "category two"],
            "/path/to/other": ["category three"]
          }
        PROMPT
      end

      def parse_batch_response(text, candidates)
        match = text.match(/\{.*\}/m)
        return {} unless match

        raw     = JSON.parse(match[0])
        valid   = candidates.map { |c| c[:path] }.to_set

        raw.each_with_object({}) do |(path, cats), result|
          next unless valid.include?(path) && cats.is_a?(Array)

          cleaned = cats.filter_map { |s| v = s.to_s.strip.downcase; v.empty? ? nil : v }.first(5)
          result[path] = cleaned unless cleaned.empty?
        end
      rescue JSON::ParserError
        {}
      end

      def dispatch(provider, dir_path, child_names, existing, max)
        case provider
        when "ollama"    then suggest_via_ollama(dir_path, child_names, existing, max)
        when "anthropic" then suggest_via_anthropic(dir_path, child_names, existing, max)
        else
          log "unknown FSDB_AI_PROVIDER '#{provider}' — skipping"
          []
        end
      end

      # ── Ollama ──────────────────────────────────────────────────────────────

      def suggest_via_ollama(dir_path, child_names, existing, max)
        base_url = ENV.fetch("FSDB_OLLAMA_URL", DEFAULT_OLLAMA_URL)
        model    = ENV.fetch("FSDB_OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL)
        prompt   = build_prompt(dir_path, child_names, existing, max)

        log "ollama #{model} → #{dir_path}"

        conn = Faraday.new(url: base_url) do |f|
          f.request :json
          f.response :raise_error
        end

        response = conn.post("/api/chat") do |req|
          req.body = { model:, stream: false, messages: [{ role: "user", content: prompt }] }
        end

        body = JSON.parse(response.body)
        text = body.dig("message", "content").to_s.strip
        suggestions = parse_text(text)
        log "  → #{suggestions.inspect}"
        suggestions
      end

      # ── Anthropic ────────────────────────────────────────────────────────────

      def suggest_via_anthropic(dir_path, child_names, existing, max)
        api_key = ENV["ANTHROPIC_API_KEY"]
        unless api_key
          log "ANTHROPIC_API_KEY not set — skipping"
          return []
        end

        model  = ENV.fetch("FSDB_AI_MODEL", "claude-opus-4-5")
        prompt = build_prompt(dir_path, child_names, existing, max)

        log "anthropic #{model} → #{dir_path}"

        conn = Faraday.new(url: ANTHROPIC_URL) do |f|
          f.request :json
          f.response :raise_error
        end

        response = conn.post do |req|
          req.headers["x-api-key"]         = api_key
          req.headers["anthropic-version"] = "2023-06-01"
          req.body = { model:, max_tokens: 256, messages: [{ role: "user", content: prompt }] }
        end

        body = JSON.parse(response.body)
        text = body.dig("content", 0, "text").to_s.strip
        suggestions = parse_text(text)
        log "  → #{suggestions.inspect}"
        suggestions
      end

      # ── Shared ───────────────────────────────────────────────────────────────

      def build_prompt(dir_path, child_names, existing, max)
        sample = child_names.first(50).join(", ")
        hint   = existing.any? ? "Existing categories (prefer reusing): #{existing.first(30).join(", ")}. " : ""

        <<~PROMPT
          You are cataloguing a filesystem for personal use.
          Directory: #{dir_path}
          Contents (sample): #{sample}
          #{hint}
          Suggest up to #{max} short topic category labels describing the human-interest subject of this directory.
          Examples: "python programming", "music", "tax documents", "machine learning", "social skills".
          Avoid generic filesystem terms like "files" or "folder".
          Reply with ONLY a JSON array of strings, e.g. ["python programming", "machine learning"]
        PROMPT
      end

      def parse_text(text)
        match = text.match(/\[.*?\]/m)
        return [] unless match

        items = JSON.parse(match[0])
        items.filter_map { |s| v = s.to_s.strip.downcase; v.empty? ? nil : v }.first(5)
      rescue JSON::ParserError
        []
      end

      def reset_failures
        @consecutive_fails = 0
      end

      def record_failure(dir_path, error)
        @consecutive_fails += 1
        log "error for #{dir_path}: #{error.message} (#{@consecutive_fails}/#{FAILURE_LIMIT} consecutive failures)"
        if @consecutive_fails >= FAILURE_LIMIT
          @circuit_open = true
          log "#{FAILURE_LIMIT} consecutive failures — giving up on AI suggestions for this run"
        end
      end

      def log(msg)
        warn "[fsdb/ai] #{msg}"
      end
    end
  end
end
