# frozen_string_literal: true

require "faraday"
require "json"

module Fsdb
  module Ai
    ANTHROPIC_URL    = "https://api.anthropic.com/v1/messages"
    DEFAULT_OLLAMA_URL   = "http://pmacs-dev-142.local:11434"
    DEFAULT_OLLAMA_MODEL = "llama3.2"
    FAILURE_LIMIT = 3

    @mutex             = Mutex.new
    @consecutive_fails = 0
    @circuit_open      = false

    class << self
      def suggest_categories(dir_path, child_names, existing_categories, max: 3)
        if @circuit_open
          log "circuit breaker open — skipping AI for #{dir_path}"
          return []
        end

        provider = ENV.fetch("FSDB_AI_PROVIDER", "ollama")

        @mutex.synchronize do
          result = dispatch(provider, dir_path, child_names, existing_categories, max)
          reset_failures
          result
        end
      rescue Faraday::Error, JSON::ParserError, StandardError => e
        record_failure(dir_path, e)
        []
      end

      # Allow tests to reset state between runs.
      def reset!
        @mutex.synchronize { @consecutive_fails = 0; @circuit_open = false }
      end

      private

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
