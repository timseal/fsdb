# frozen_string_literal: true

require "thor"
require "tty-table"
require "tty-tree"
require "tty-progressbar"
require "pastel"

module Fsdb
  class Cli < Thor
    class_option :db, type: :string, desc: "Path to catalogue DB (overrides FSDB_DB env var)"

    # ── scan ──────────────────────────────────────────────────────────────────

    desc "scan PATH", "Walk PATH, detect content types, store in catalogue"
    option :ai,         type: :boolean, default: false, desc: "Use AI to suggest topic categories"
    option :provider,   type: :string,                  desc: "AI provider: ollama (default) or anthropic"
    option :batch_size, type: :numeric, default: 10,    desc: "Directories per AI request"
    option :yes,        type: :boolean, default: false, aliases: "-y", desc: "Skip AI confirmation prompt"
    def scan(path)
      with_db do |db|
        root = File.expand_path(path)
        error_exit("#{root} does not exist") unless File.exist?(root)

        ENV["FSDB_AI_PROVIDER"] = options[:provider] if options[:provider]

        pastel  = Pastel.new
        scanner = Scanner.new(db, root)

        # ── Phase 1: filesystem walk ────────────────────────────────────────
        bar    = TTY::ProgressBar.new("Scanning [:bar]", total: nil, width: 30, clear: true)
        result = scanner.scan { bar.advance }
        bar.finish
        puts pastel.green("Scanned") + " #{result[:files]} files, #{result[:dirs]} dirs."

        # ── Phase 2: AI suggestions ─────────────────────────────────────────
        return unless options[:ai]

        batch_size = options[:batch_size]
        candidates = scanner.ai_candidate_dirs
        n_requests = (candidates.size.to_f / batch_size).ceil

        if candidates.empty?
          puts "No directories eligible for AI suggestions."
          return
        end

        model    = ENV.fetch("FSDB_OLLAMA_MODEL", Ai::DEFAULT_OLLAMA_MODEL)
        provider = ENV.fetch("FSDB_AI_PROVIDER", "ollama")
        puts "\n#{pastel.bold("AI suggestions")}"
        puts "  Provider   : #{provider} (#{model})"
        puts "  Directories: #{candidates.size}"
        puts "  Batch size : #{batch_size} dirs/request"
        puts "  Requests   : #{n_requests}"

        unless options[:yes]
          print "\nProceed? [y/N] "
          return unless $stdin.gets.to_s.strip.downcase == "y"
        end

        ai_bar = TTY::ProgressBar.new(
          "  Requesting [:bar] :current/:total",
          total: n_requests, width: 30,
        )

        assigned = scanner.suggest_in_batches(candidates, batch_size:) do |_i, _total|
          ai_bar.advance
        end
        ai_bar.finish

        puts pastel.green("Done.") + " Assigned #{assigned} category tag(s) across #{candidates.size} directories."
      end
    end

    # ── tag ───────────────────────────────────────────────────────────────────

    desc "tag PATH", "Assign a topic category to PATH"
    option :category,  type: :string,  required: true, aliases: "-c", desc: "Category name"
    option :propagate, type: :boolean, default: false,  aliases: "-p", desc: "Also tag all catalogued children"
    def tag(path)
      with_db do |db|
        p = Tagger.normalize(path)
        db.transaction { Tagger.assign(db, p, options[:category], propagate: options[:propagate]) }
        suffix = options[:propagate] ? " (and all children)" : ""
        pastel = Pastel.new
        puts "#{pastel.green("Tagged")} #{p}#{suffix} → #{pastel.bold(options[:category])}"
      end
    rescue Tagger::NotCatalogued => e
      error_exit(e.message)
    end

    # ── untag ─────────────────────────────────────────────────────────────────

    desc "untag PATH", "Remove a category from PATH"
    option :category,  type: :string,  required: true, aliases: "-c", desc: "Category name"
    option :propagate, type: :boolean, default: false,  aliases: "-p", desc: "Also untag all catalogued children"
    def untag(path)
      with_db do |db|
        p = Tagger.normalize(path)
        db.transaction { Tagger.remove(db, p, options[:category], propagate: options[:propagate]) }
        pastel = Pastel.new
        puts "#{pastel.yellow("Untagged")} #{p} → #{options[:category]}"
      end
    rescue Tagger::NotCatalogued => e
      error_exit(e.message)
    end

    # ── search ────────────────────────────────────────────────────────────────

    desc "search", "Search catalogue by category and/or content type"
    option :category,  type: :string,  aliases: "-c", desc: "Filter by category"
    option :type,      type: :string,  aliases: "-t", desc: "Filter by content type (video, ebook, …)"
    option :under,     type: :string,  aliases: "-u", desc: "Restrict to subtree"
    option :dirs,      type: :boolean, default: false, desc: "Directories only"
    option :limit,     type: :numeric, default: 200,  aliases: "-n", desc: "Max results"
    def search
      with_db do |db|
        entries = Query.search(
          db,
          category:     options[:category],
          content_type: options[:type],
          path_prefix:  options[:under],
          dirs_only:    options[:dirs],
          limit:        options[:limit],
        )

        if entries.empty?
          puts "No results."
          return
        end

        table = TTY::Table.new(
          header: %w[Path Type Categories],
          rows:   entries.map { |e| [e.path, e.display_type, e.categories.join(", ")] },
        )
        puts table.render(:unicode, padding: [0, 1], multiline: true)
        puts Pastel.new.dim("#{entries.size} result(s)")
      end
    end

    # ── ls ────────────────────────────────────────────────────────────────────

    desc "ls [PATH]", "List catalogue entries under PATH with their tags"
    option :depth, type: :numeric, default: 1, aliases: "-d",
                   desc: "Depth (1=immediate children, 0=unlimited)"
    def ls(path = ".")
      with_db do |db|
        p      = File.expand_path(path)
        depth  = options[:depth].zero? ? nil : options[:depth]
        entries = Query.list_under(db, p, depth:)

        if entries.empty?
          puts "No catalogued entries under #{p}. Run 'fsdb scan #{p}' first."
          return
        end

        tree_data = build_tree_hash(entries, p)
        puts TTY::Tree.new(tree_data).render
      end
    end

    # ── stats ─────────────────────────────────────────────────────────────────

    desc "stats", "Show catalogue summary statistics"
    def stats
      with_db do |db|
        s      = Query.stats(db)
        pastel = Pastel.new

        puts pastel.bold("Catalogue summary")
        puts "  Entries : #{s[:total_entries]} (#{s[:total_files]} files, #{s[:total_dirs]} dirs)"
        puts "  Total   : #{humanize_bytes(s[:total_size])}"
        puts

        if s[:by_type].any?
          puts pastel.bold("By content type")
          type_table = TTY::Table.new(
            header: %w[Type Files Size],
            rows:   s[:by_type].map { |r| [r[:type], r[:count], humanize_bytes(r[:size])] },
          )
          puts type_table.render(:unicode, padding: [0, 1])
          puts
        end

        if s[:top_categories].any?
          puts pastel.bold("Top categories")
          cat_table = TTY::Table.new(
            header: %w[Category Entries],
            rows:   s[:top_categories].map { |r| [r[:name], r[:count]] },
          )
          puts cat_table.render(:unicode, padding: [0, 1])
          puts
        end

        puts "  Uncategorised: #{s[:uncategorised]} entries"
      end
    end

    private

    def with_db(&block)
      db_path = options[:db] || ENV["FSDB_DB"]
      DB.open(db_path, &block)
    end

    def error_exit(msg)
      warn Pastel.new.red("Error: #{msg}")
      exit(1)
    end

    def truncate(str, max)
      str.length > max ? "…#{str[-(max - 1)...]}" : str
    end

    def humanize_bytes(bytes)
      return "0 B" if bytes.nil? || bytes.zero?

      units = %w[B KB MB GB TB]
      exp   = (Math.log(bytes) / Math.log(1024)).floor
      exp   = units.length - 1 if exp >= units.length
      format("%.1f %s", bytes.to_f / (1024**exp), units[exp])
    end

    def build_tree_hash(entries, base)
      # Build a nested hash for TTY::Tree: { "label" => { children... } or [] }
      tree = {}
      entries.each do |entry|
        label = entry.path.delete_prefix("#{base}/")
        label += "  [#{entry.display_type}]" unless entry.dir?
        label += "  (#{entry.categories.join(", ")})" if entry.categories.any?
        tree[label] = []
      end
      { base => tree }
    end
  end
end
