## RoboRuby Ruby AI Newsletter Summary – Issue 29 (April 30, 2026)

### 🔥 **Headline Story: Ruby's I/O Revolution for AI Workloads**

Performance is now the narrative. [Carmine Paolino's work on Solid Queue](https://paolino.me/solid-queue-doesnt-need-a-thread-per-job/) shows fiber-based concurrency nets **12% throughput gains** for LLM streaming tasks—and [Shopify just proved it scales](https://speakerdeck.com/ioquatix/surviving-black-friday-329-billion-requests-with-falcon): 329 billion requests during 2025 Black Friday on Falcon (Samuel Williams' fiber-based server), peaking at 1.5M req/sec with zero drops. The message is clear: threads are legacy; fibers are the future for AI-heavy I/O patterns that spend 99% of their time waiting on tokens and webhooks. Ruby's defaults are catching up to its workloads.

---

### **Headline Story #2: Matz Ships a Compiler in a Month (with Claude)**

[Spinel](https://github.com/matz/spinel)—Matz's new ahead-of-time Ruby compiler built in ~30 days with Claude as co-author—produces standalone native executables via whole-program type inference and optimized C emission. The kicker: it drops `eval`, `instance_eval`, `class_eval`, `send`, `method_missing`, and `define_method`. Dynamic metaprogramming was always about code compression for humans; with AI writing the alternative on your behalf, static Ruby becomes viable. At RubyKaigi, Matz revealed 1/3 of Ruby core already writes 50% of code with AI; he writes 100% his way. [Sam Ruby's Roundhouse transpiler](https://intertwingly.net/blog/2026/04/28/Round-Trip.html) proves the concept: two `make` commands from a fresh clone yield a real Rails app running on localhost as a single native binary. The door to Spinel-compiled Rails is open.

---

### **Headline Story #3: Rails Gets Its First AI-Native Command**

[`rails query` shipped in Rails 8.2](https://github.com/basecamp/console1984/pull/154)—a CLI designed for AI agents to safely examine production databases with **structured JSON output** instead of unstructured strings. It prevents destructive commands, returns explicit `columns`, `rows`, and `meta`, provides pagination cursors and generated SQL, and emits auditable `query.rails` notifications. Lewis Buckley also released a [Claude Code skill](https://github.com/lewispb/rails-query-skill) teaching Claude to translate natural questions into `bin/rails query` calls. This is Rails designing agent-native interfaces directly into the runtime—not documentation, not third-party gems.

---

### **Notable Gems & Tools**

- **[LLM Cost Tracker](https://github.com/sergey-homenko/llm_cost_tracker)** — Logs every LLM API call with token counts, costs, latency; includes a mountable dashboard and budget guardrails.
- **[Ragents](https://github.com/activeagents/ragents)** — Ruby AI agent framework using Ractors for isolated parallel execution; near-linear scaling for agent swarms on Ruby 4.x.
- **[Inkmark](https://github.com/yaroslav/inkmark)** — AI-first Markdown gem (built on Rust's pulldown-cmark) for RAG pipelines with heading-based chunking, block-aware truncation, and structured extraction.
- **[Kernai](https://github.com/Eth3rnit3/kernai)** — Minimal agentic framework with deterministic loops, progressive skill discovery, and MCP integration for lightweight portability.
- **[Kreuzcrawl](https://github.com/kreuzberg-dev/kreuzcrawl)** — High-performance Rust web crawler with Ruby bindings, MCP server for agents, and headless browser rendering.
- **[llm.rb v5.4.0](https://0x1eef.github.io/x/llm.rb/file.CHANGELOG.html)** — Database persistence for contexts, agentic loops, context compaction, and scoped MCP client lifecycle.

---

### **Key Articles & Tutorials**

- **[Ruby Concurrency: What Actually Happens](https://paolino.me/ruby-concurrency-what-actually-happens/)** — Carmine's definitive explainer on fibers vs. threads, addressing real questions from the community with corrections from core committer Jean Boussier.
- **[PII Filtering for RubyLLM with Top Secret](https://thoughtbot.com/blog/ruby-llm-top-secret)** — Steve Polito on filtering sensitive data before sending to LLM providers; integrates cleanly with ActiveRecord chats.
- **[Claude Code for the Semi-Reluctant Rails Developer](https://robbyonrails.com/claude-code-curious-rails-developers/)** — Robby Russell's practical guide on model selection, testing workflows, debugging, and minimal CLAUDE.md configuration.
- **[Rails Security Auditor](https://maquina.app/documentation/ai-tools/rails-security-auditor/)** — Claude Code plugin that scans Rails apps across 10 security categories and can auto-fix issues.

---

### **Quick Takes**

- 🎯 **New Announcements:** [Compound Engineering v3](https://x.com/trevin/status/2047066108763770998) unified the agentic plugin namespace; [Ruby CrewAI](https://github.com/MuhammadIbtisam/ruby-crewai) wraps CrewAI's HTTP API for multi-agent orchestration; [RailsPress](https://railspress.org/) is a mountable Rails 8 blogging engine with AI-agent-friendly REST APIs.
- 🏗️ **Tools for Agents:** [Stripe Link for Agents](https://x.com/stripe/status/2049529444092838116) lets AI spend on user behalf via scoped merchant tokens; [Cursor's @cursor/sdk](https://cursor.com/blog/typescript-sdk) exposes its own runtime so you can run coding agents from CI/CD; [Cloudflare Artifacts](https://blog.cloudflare.com/artifacts-git-for-agents-beta/) is a Git-compatible versioned filesystem for agent state.
- 📊 **Model Sizing:** Bojie Li's [Incompressible Knowledge Probes](https://01.me/research/ikp/) calibrate closed LLM sizes—GPT-5.5 at ~9T params, Claude Opus at ~4.7T, Gemini 2.5 Pro at ~1.2T.
- 🎤 **Conference Alert:** [Rails World 2026](https://rubyonrails.org/2026/4/23/big-rails-world-2026-update-CFP) (Sept 23–24 in Austin) now emphasizes AI-native development; CFP closes May 16th.
- 📈 **Community Pulse:** [2026 Rails Community Survey](https://blog.planetargon.com/blog/entries/the-2026-ruby-on-rails-community-survey-is-open) now asks about AI tool usage, JS frameworks, and infrastructure—open through July 3rd.

---

**Bottom Line:** Ruby's ecosystem is doubling down on event-driven I/O, native compilation, and agent-native tooling. The era of threads-by-default and human-first interfaces is over. If your Rails app handles long-tail I/O or needs production-safe agent introspection, the framework is building for you now.
