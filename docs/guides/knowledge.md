# Knowledge & Retrieval

Facilities for searching and retrieving knowledge from a robot's history and from external documents:

- **Chat History Search** — semantic search over accumulated conversation turns
- **Embedding-Based Document Store** — lightweight RAG: store arbitrary text, search by meaning

---

## Chat History Search

### The Problem

Long-running robots accumulate many conversation turns. When you need to recall what was discussed earlier on a specific topic, re-sending the full history wastes tokens. `search_history` gives you a focused slice of the most relevant past messages without touching the LLM.

### robot.search_history

```ruby
results = robot.search_history(query, limit: 5)
```

Scores every message in the robot's conversation history against `query` using stemmed term-frequency cosine similarity (via the `classifier` gem). Returns up to `limit` `HistoryResult` objects sorted by score descending.

```ruby
results = robot.search_history("quarterly revenue", limit: 3)

results.each do |r|
  puts "[#{r.role}] score=#{r.score.round(3)} idx=#{r.index}"
  puts "  #{r.text}"
end
```

### HistoryResult Fields

| Field | Type | Description |
|-------|------|-------------|
| `text` | String | The message text |
| `role` | Symbol | `:user`, `:assistant`, or `:system` |
| `score` | Float (0.0–1.0) | Cosine similarity with the query |
| `index` | Integer | Position in `@chat.messages` |

### Typical Scores

| Relationship | Typical Score |
|---|---|
| Direct answer to the query | 0.50 – 0.80 |
| Same topic, different phrasing | 0.20 – 0.50 |
| Unrelated | < 0.10 |

### Short Messages

Messages shorter than 20 characters are skipped — they produce no meaningful term vector.

### Full Example

```ruby
robot = RobotLab.build(name: "analyst", system_prompt: "You are a financial analyst.")

# … after several robot.run() calls …

hits = robot.search_history("customer acquisition cost")
hits.each { |r| puts "#{r.role} (#{r.score.round(2)}): #{r.text}" }
```

### RAG Pattern — Retrieve Then Generate

Use `search_history` to inject only the relevant past context into the next call:

```ruby
hits    = robot.search_history(user_query, limit: 3)
context = hits.map(&:text).join("\n")

robot.run("Recall context:\n#{context}\n\nNew question: #{user_query}")
```

### Optional Dependency

`search_history` requires the `classifier` gem:

```ruby
gem "classifier", "~> 2.3"
```

Without it, calling `search_history` raises `RobotLab::DependencyError` with an install hint.

---

## Embedding-Based Document Store

### The Problem

Sometimes the knowledge you need isn't in the conversation history — it's in a README, a product spec, a changelog. `store_document` / `search_documents` embed arbitrary text with `fastembed` and retrieve the most relevant chunk at query time.

### memory.store_document / memory.search_documents

```ruby
memory.store_document(:readme,    File.read("README.md"))
memory.store_document(:changelog, File.read("CHANGELOG.md"))

hits = memory.search_documents("how to configure redis", limit: 3)
hits.each { |h| puts "#{h[:key]} (#{h[:score].round(3)}): #{h[:text][0..80]}" }
```

Each result hash contains:

| Key | Type | Description |
|-----|------|-------------|
| `:key` | Symbol | The key the document was stored under |
| `:text` | String | The full stored text |
| `:score` | Float (0.0–1.0) | Cosine similarity with the query |

### Standalone DocumentStore

The `Memory` methods delegate to `RobotLab::DocumentStore`, which can also be used directly:

```ruby
store = RobotLab::DocumentStore.new
store.store(:doc_a, "Ruby on Rails is a full-stack web framework.")
store.store(:doc_b, "Postgres is an advanced relational database.")

results = store.search("relational database SQL", limit: 2)
puts results.first[:key]  # => :doc_b
```

Management methods:

```ruby
store.size          # => 2
store.keys          # => [:doc_a, :doc_b]
store.empty?        # => false
store.delete(:doc_a)
store.clear
```

### Embedding Model

Default: `BAAI/bge-small-en-v1.5` (~23 MB, downloaded on first use, cached in `~/.cache/fastembed/`).

Documents are embedded with a `"passage: "` prefix and queries with `"query: "` prefix — the standard retrieval convention for BGE models.

Custom model:

```ruby
store = RobotLab::DocumentStore.new(model_name: "BAAI/bge-base-en-v1.5")
```

### RAG Pattern

```ruby
# 1. Index your knowledge base at startup
memory.store_document(:readme,    File.read("README.md"))
memory.store_document(:changelog, File.read("CHANGELOG.md"))
memory.store_document(:api_docs,  File.read("docs/api.md"))

# 2. At query time, retrieve the most relevant chunks
hits    = memory.search_documents(user_query, limit: 3)
context = hits.map { |h| h[:text] }.join("\n\n")

# 3. Pass context to your robot
result = robot.run("Use the following context:\n#{context}\n\nQuestion: #{user_query}")
```

### Memory API Summary

| Method | Description |
|--------|-------------|
| `memory.store_document(key, text)` | Embed and store a document |
| `memory.search_documents(query, limit: 5)` | Search by semantic similarity |
| `memory.document_keys` | List stored keys |
| `memory.delete_document(key)` | Remove a document |

### Dependency

`fastembed` is a core RobotLab dependency — no optional gem required. The ONNX model is downloaded on first use.

---

## See Also

- [Observability Guide](observability.md)
- [Example 25 — Chat History Search](../../examples/25_history_search.rb)
- [Example 26 — Embedding-Based Document Store](../../examples/26_document_store.rb)
