# fsdb

Filesystem catalogue with content-type detection and user-focused topic tagging.
Backed by SQLite. Rails frontend planned.

## Install

```bash
bundle install
chmod +x bin/fsdb
```

## Commands

```bash
# Scan a directory (detect content types, store in catalogue)
bin/fsdb scan ~/Documents

# Scan with AI-suggested topic categories (prompts for confirmation first)
bin/fsdb scan ~/Documents --ai

# Skip confirmation
bin/fsdb scan ~/Documents --ai --yes

# Assign a topic category manually
bin/fsdb tag ~/Documents/Books --category "reference" --propagate

# Remove a category
bin/fsdb untag ~/Documents/Books --category "reference"

# Search
bin/fsdb search --category "python programming"
bin/fsdb search --type ebook
bin/fsdb search --under ~/Documents --type video

# List entries under a path
bin/fsdb ls ~/Documents --depth 2

# Summary statistics
bin/fsdb stats
```

## AI suggestions

`fsdb scan --ai` runs a two-phase process:

1. **Filesystem scan** — walks the tree, detects content types, writes to SQLite.
2. **AI suggestions** — queries catalogued directories, shows a request count, asks for
   confirmation, then sends batches to the AI provider.

Before any API calls are made you will see:

```
AI suggestions
  Provider   : ollama (gemma3:12b)
  Directories: 142
  Batch size : 10 dirs/request
  Requests   : 15

Proceed? [y/N]
```

### Batch prompting

Instead of one API call per directory, fsdb packs multiple directories into a single
prompt and parses a JSON object back. This follows the **batch prompting** technique —
see [Cheng et al., 2023 — *Batch Prompting: Efficient Inference with LLM APIs*](https://arxiv.org/abs/2301.08721).

A circuit breaker stops AI calls after 3 consecutive failures. Calls are serialised
(one at a time) to avoid overloading the Ollama server.

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `FSDB_AI_PROVIDER` | `ollama` | `ollama` or `anthropic` |
| `FSDB_OLLAMA_URL` | `http://pmacs-dev-142.local:11434` | Ollama server |
| `FSDB_OLLAMA_MODEL` | `gemma3:1b` | Model name |
| `FSDB_AI_MODEL` | `claude-opus-4-5` | Anthropic model |
| `FSDB_AI_MAX_DEPTH` | `3` | Max directory depth for AI suggestions |
| `FSDB_DB` | `~/.local/share/fsdb/fsdb.db` | SQLite database path |

## Content types detected

`video` · `audio` · `image` · `ebook` · `document` · `code` · `archive` · `data` · `font`

## Future

- Extended metadata per content type (track length, image dimensions, etc.)
- Rails frontend for browsing and managing the catalogue
