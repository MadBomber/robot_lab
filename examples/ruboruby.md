---
url: https://rubyai.beehiiv.com/p/ruby-ai-news-april-30th-2026
title: Ruby AI News - April 30th, 2026
description: Ruby's agentic future is speeding up
access_date: 2026-05-04T21:45:47.000Z
current_date: 2026-05-04T21:45:47.730Z
---

* RoboRuby
* Posts
* Ruby AI News - April 30th, 2026

# Ruby AI News - April 30th, 2026

## Ruby's agentic future is speeding up

![Author](IMAGE) 

Matt Solt  
 April 30, 2026 

 Welcome to the 29th edition of Ruby AI News! This edition features performance optimizations for agentic workloads, Matz’s new Ruby compiler, Rails’ progression to an AI-native framework, and much more. 

Read on the web

## Contents

* Top Stories  
   * Performance Optimizations for Agentic Workloads  
   * Matz is all-in on AI  
   * A Core Rails Command for AI Agents
* Need to Know AI News
* Content  
   * Announcements  
   * Articles  
   * Videos  
   * Podcasts  
   * Discussions  
   * Additional Reading
* Events  
   * Previous  
   * Upcoming
* Open Source Updates  
   * Code Spotlight  
   * New Gems  
   * New Open Source
* Jobs & Opportunities  
   * Featured
* One Last Thing

## Top Stories

### Performance Optimizations for Agentic Workloads

 Carmine Paolino, the author of RubyLLM and creator at Chat with Work, is bringing Ruby into the future with his work on Solid Queue, Rails 8's default job processor. On "Solid Queue Doesn't Need a Thread Per Job", Carmine reports that swapping `threads: 10` for `fibers: 100` in Solid Queue's config yielded an almost 12 percent increase in throughput on production-like RubyLLM streaming workloads. The math is most prominent at the database layer: thread mode needs `threads + 2` connections per process, so 50 concurrent jobs across 6 processes burns 312 connection, well past PostgreSQL's default `max_connections` of 100\. Fiber mode for I/O-heavy work shares one executor thread per process, dropping that to about 60\. 

 Meanwhile, at RubyKaigi 2026, Samuel Williams presented how Shopify's Storefront Renderer served 329 billion requests during 2025’s Black Friday/Cyber Monday weekend, peaking at almost 1.5 million requests per second and 85 million requests per minute with zero dropped requests, all on Falcon, Samuel's fiber-based asynchronous Ruby web server. Brad Gessler highlighted the importance of the work the Shopify team is doing: "Glad to see (Ilya Grigorik and Samuel Williams) working on improving Ruby's IO story! Their success is going to unlock a ton of new capabilities for the apps we can build with Ruby." Two performance streams converging. Carmine attacking the job-queue layer, Samuel and Shopify proving the request-handling layer at scale, both pulling Ruby toward the event-driven I/O model necessary for Ruby’s agentic future. 

 Carmine's follow-up, "Ruby Concurrency: What Actually Happens", is a clear explainer answering the questions that came back at him: what happens when a fiber blocks, do you still need threads, what about transactions, what about Ractors. The r/ruby thread drew substantive corrections from Ruby core committer Jean Boussier: Active Record connection management behaves the same for threads and fibers, and the OS scheduler is less of a cost than the post initially implied because Ruby parks threads until they're signaled, and Carmine iterated the post in response, the kind of review cycle the Ruby community does well. The throughline that matters for AI-heavy Rails apps is that LLM streaming jobs spend 99% of their time waiting for tokens, HTTP fanout to providers spends most of its time waiting for responses, and webhook-heavy integrations spend most of their time waiting on the network. Fibers are the right primitive for that workload shape; threads were chosen when most of Ruby's I/O looked like a quick database round-trip, and Solid Queue defaulting to threads is an artifact of that older world. The AI workloads pushing Ruby into longer-tail I/O are forcing the framework's defaults to catch up. 

### Matz is all-in on AI 

 Yukihiro Matsumoto (Matz) introduced Spinel (named after his new cat), an ahead-of-time Ruby compiler that produces standalone native executables, built in roughly a month with Claude as co-author. Spinel does whole-program type inference and emits optimized C. The compiler is self-hosting, with its backend written in Ruby and compiled to a native binary by itself. One hacker news commenter captured the possibilities: "AI will turn 10x programmers into 100x programmers. Or in Matz's case maybe 100x programmers into 500x." 

 What does Spinel says about AI's role in Ruby's future? Matz argued for programmer happiness through metaprogramming, and Spinel drops `eval`, `instance_eval`, `class_eval`, `send`, `method_missing`, and `define_method`, some of the most prominent features associated with Ruby. Metaprogramming was always a code-compression tool for humans, and that shifts when an LLM writes and reads the alternative on your behalf. The same workflow that lets Matz ship a compiler in a month also makes the language he's compiling less reliant on the dynamic nature that made it slow to compile in the first place. At RubyKaigi, Matz revealed that roughly a third of Ruby core committers already write 50 percent of their code with AI, and he says he writes 100 percent of his code that way. The open question isn't whether AI can ship a compiler, but whether a human-led team can maintain what AI shipped. 

 In Round Trip, Sam Ruby iterated on Roundhouse, a transpiler that lowers idiomatic Ruby into a Spinel-compatible subset. Two `make` commands from a fresh clone produce a real Rails app, models, validations, Turbo Stream broadcasts, and SQLite persistence running on localhost. It has compiler issues, but Matz shipped a fix for default argument values based on Roundhouse's feedback. Sam's framing "requests per second per gigabyte of resident memory" may push organizations off Ruby toward Go or Rust. But Spinel plus Roundhouse points at a future where a Rails app can ship as a single native executable without leaving the language, in a Ruby ecosystem where its creator writes a compiler in a month because his collaborator is Claude. 

### A Core Rails Command for AI Agents

 Lewis Buckley merged a `rails query` command into Rails core, adding a CLI command designed for AI agents and automated tooling to safely examine production databases. The feature, scheduled to ship in Rails 8.2, came out of a real world AI use case. Lewis wrote ithat "agents and automated tooling increasingly need to query production databases to answer questions, investigate issues, and gather context," and the closest existing option, `rails runner`, returned unstructured strings, allowed destructive commands, and had no pagination. Tomoya Yoshida summed up the shift in plain terms: rails runner's output "wasn't AI-readable," while `rails query` returns structured JSON. 

 What `rails query` does is tightly scoped. It executes ActiveRecord expressions or raw SQL and returns JSON with explicit `columns`, `rows`, and `meta`, providing execution time, pagination cursors, the generated SQL, all the things an LLM needs to ground its next decision instead of regex-parsing a console dump. Three subcommands give agents reusable primitives without a custom MCP server: `query schema [TABLE]` for introspection, `query models` for the Active Record class graph with associations, and `query explain` for query plans. Writes are blocked at the connection level rather than by convention, the command connects to read replicas by default, and `--page--per` keep result sets bounded for context windows. Every invocation emits a `query.rails` Active Support Notification, turning each agent query into something a host application can subscribe to, log, and audit. 

 Additionally, Lewis shipped a Claude Code skill that teaches Claude to translate questions like "how many active users do we have?" into `bin/rails query` or `bin/kamal query` calls against deployed apps, and he opened a Console 1984 pull request that subscribes to the `query.rails` notification to record every invocation as a session tagged with the agent and user that ran it. Together that's the first end-to-end Rails-native pattern for letting AI agents read production safely with an auditable trail. It shows that Rails was serious when it updated its tagline to read "Ruby on Rails scales from PROMPT to IPO. Token-efficient code that's easy for agents to write and beautiful for humans to review." `rails query` is the framework starting to design agent-native interfaces directly into the runtime, providing structured output, write barriers, audit hooks, rather than leaving them to documentation or third-party gems. 

## Need to Know AI News

DESIGN.md Format Is Now Open Source for Designers Google Labs open-sourced the draft DESIGN.md specification, with a demo from David East, pitching it as the AGENTS.md analog for design systems: a portable spec that lets AI agents export design rules across projects, know what each color is for, and validate choices against WCAG. 

Build Programmatic Agents With the Cursor SDK Roshan Sadanani launched Cursor's @cursor/sdk TypeScript package, exposing the runtime, harness, and Composer 2 model that power Cursor itself so developers can run coding agents from CI/CD pipelines, embed them in products, or deploy them on Cursor's cloud VMs with sandboxing, MCP support, and subagent delegation. 

Artifacts: Versioned Storage That Speaks Git Dillon Mulroy, Matt Carey, and Matt Silverlock launched Cloudflare's versioned filesystem for AI agents that exposes a Git-compatible API because "agents know Git" from training data, with Cloudflare using it internally to persist per-session state so agents can fork from any prior point. 

Give Your Agent a Wallet You Control Stripe launched Link for Agents, a wallet letting AI agents spend on a user's behalf via one-time cards or merchant-scoped tokens, with credentials never exposed, every purchase user-approved, and skill.md-based authentication compatible with Claude, OpenClaw, and custom agents. 

Incompressible Knowledge Probes Bojie Li of Pine AI posted that "closed labs hide model sizes - they can't hide what their models know," then released IKP, a 1,400-question, 7-tier benchmark across 188 models that calibrates a log-linear curve to size closed LLM APIs at GPT-5.5 \~9T, Claude Opus 4.7 \~4T, and Gemini 2.5 Pro \~1.2T parameters. 

## Content

### Announcements

LLM Cost Tracker Sergii Khomenko created a Rails gem that logs every LLM API call to the database with token counts, costs, latency, and custom tags. Supports most LLM providers through auto-instrumentation and Faraday middleware. Includes budget guardrails and a mountable dashboard while storing no prompt or response content. 

Ragents Justin Bowen released a Ruby AI agent framework using Ractors for isolated parallel execution, with RubyLLM integration. In a RubyKaigi 2026 talk, Justin demonstrated how Ruby 4.x's Ractor-Local GC enables near-linear scaling for autonomous agent swarms by bridging heap compaction with context management. 

Inkmark Yaroslav Markin built an AI-first Markdown gem for Ruby built on Rust's pulldown-cmark. Designed for RAG pipelines, it provides heading-based and sliding-window chunking with overlap, block-aware truncation for context-window budgeting, plain-text extraction for embeddings, and structured element extraction with byte ranges. 

Compound Engineering v3 Trevin Chow shared a major release of the agentic engineering plugin: every skill now lives under a unified `ce-` namespace, brainstorm and plan artifacts carry stable IDs that trace requirements from idea to commit, reviewers walk findings one at a time instead of rubber-stamping, and Codex, Pi, and Copilot all get first-class installs alongside Claude Code. 

Kernai Eth3rnit3 released a minimal Ruby agent framework built on a universal structured block protocol with a deterministic execution loop. Agents discover commands progressively rather than receiving all definitions upfront, keeping context light and enabling portability across models including smaller ones without native tool calling. Supports MCP integration, sub-agent workflows, and multimodal inputs. 

Autoresearching Ruby Performance with LLMs Nate Berkopec presented at RubyKaigi 2026 on using LLM agents in automated loops to brute-force Ruby performance optimization. Nate identified four loop patterns (agent, ralph, autoresearch, factory) with increasing gate complexity, arguing that gate and eval design matters more than prompt or skill design. 

Ruby CrewAI Muhammad Ibtisam Hussain released a minimal Ruby client for CrewAI's async managed process HTTP API. The gem wraps crew kickoff, status polling, input discovery, and human-in-the-loop workflow resumption, letting Ruby developers orchestrate multi-agent AI crews without handling raw HTTP. 

RubyLLM Skills for Coding Agents Kaka Ruto created a collection of 14 Claude Code skills for working with the RubyLLM gem. Skills cover agents, audio transcription, embeddings, image generation, MCP integration, moderation, OpenTelemetry instrumentation, Rails integration, and tool building. 

Kreuzcrawl Kreuzberg released a high-performance Rust web crawling engine with native bindings for Ruby. Features include structured data extraction, built-in MCP server integration for AI agents, streaming crawl events, batch operations with partial failure tolerance, and headless browser rendering for JavaScript-heavy SPAs. 

Rails Security Auditor Mario Chávez shared a Claude Code plugin that scans Rails apps across 10 security categories including CSRF, CSP, session configuration, rate limiting, and gem vulnerabilities. The auditor detects the Rails version to apply version-appropriate checks, grades findings by severity, and can automatically fix identified issues. 

Claude Code for the Semi-Reluctant, Somewhat Curious Ruby on Rails Developer Robby Russell updated his guide covering model selection (Sonnet for daily tasks, Opus for complex reasoning), testing workflows with RSpec and Minitest, debugging with error monitoring integration, and configuration strategies using scoped rules and minimal CLAUDE.md files. 

llm.rb v5.4.0 Robert reached v5.4.0 of the llm.rb library. Recent changes include database persistence for contexts and agents, configurable tool concurrency, context compaction for long-lived conversations, loop guards for stuck agentic loops, prompt transformers, directory-backed skills, and scoped MCP client lifecycle. 

Ruby Upgrade Toolkit Dhruva Sagar released a Claude Code plugin for safely upgrading Ruby and Rails projects. Slash commands audit breaking changes, generate phased roadmaps, and apply fixes incrementally. Ruby phases complete before Rails phases, intermediate versions are handled automatically, and the process pauses on failure for manual recovery. 

RailsPress Avi Flombaum launched a mountable Rails 8 engine that adds blogging and CMS capabilities with an entity system for admin-managing any ActiveRecord model, inline editing via Turbo Streams, and versioned CMS blocks. The REST API was designed for AI agents with one-time bootstrap keys and capability discovery. 

Lowfidelity Abhishek Parolkar released a Rails gem that toggles any app into a hand-drawn black-and-white wireframe view. Rack middleware injects CSS that desaturates colors, replaces fonts with handwriting styles, and fades images, activated via a floating button for design reviews and stakeholder presentations. Not AI, but still interesting for unpacking AI generated work. 

Great Big Rails World 2026 Update: CFP, Corporate Support Tickets, Workshops Amanda Perino announced that Rails World 2026 returns September 23-24 in Austin, Texas, with a CFP closing May 16th that features AI-native development and Rails + AI / agentic systems as primary themes, plus new hands-on workshops on September 22 prioritizing those same AI tracks. 

The 2026 Ruby on Rails Community Survey Is Open Autumn Morgan shared that Planet Argon launched the ninth edition of their Rails community survey, open through July 3rd. The 2026 survey added questions on AI tool usage in development workflows, JavaScript framework preferences, and infrastructure priorities. 

### Articles

PII Filtering for RubyLLM with Top Secret Steve Polito demonstrated RubyLLM::TopSecret, a gem that filters personally identifiable information before sending messages to LLM providers. The gem replaces PII with placeholders like `[PERSON_1]` and restores original values in responses, integrating via `acts_as_filtered_chat` for ActiveRecord-backed chats. 

Stop Reading AI Code. Start Measuring It. A Rails Playbook Paulo Tarso built a quality gate system for validating AI-generated Rails code using automated metrics instead of manual review. The playbook combined SimpleCov for coverage, Flog for complexity, RuboCop for module size, and Mutant for mutation testing into a single `bin/rake quality` command with ratcheting thresholds. 

AIA v1.1.0: Give Your AI Skills and a Personality Dewayne VanHoozer released a new version of his Ruby CLI AI assistant adding Skills for structured process knowledge following the SKILL.md convention and Roles for persistent personas. Skills support composition and progressive disclosure, while Roles define character traits and interaction patterns across chat sessions. 

Building an Agentic AI System in Ruby on Rails with RubyLLM Francis Karuri built a TV show cancellation predictor using Rails, RubyLLM, and Google Gemini that autonomously orchestrates six research tools to gather critic scores, network history, production news, and cast social media data before synthesizing a survival forecast. 

Claude Skills for RSpec to Minitest Migration Swarms Viktor Schmidt evolved his multi-agent Claude Code pipeline to V3, replacing prompt prose with regex-enforced validator gates and Claude Skills across nine deterministic checkpoints. The pattern catalog grew from 40 to 169 rules over six weeks of Rails monolith migration, with each addition triggered by a specific recurring failure. 

Artifacts Are Alive (And Photographs Are Dead) Scott Werner argued that AI tools like Claude have made interactive browser-based artifacts a viable medium for communicating ideas, replacing static documents the way explorable explanations replace photographs. He announced Artifact.land, a social platform built by Sublayer for sharing, discovering, and forking these interactive HTML/JavaScript creations. 

Ruby Is All You Need (Part II) Paulo Henrique Castro continued his series on building LLM evaluation pipelines in pure Ruby on Rails. Part II added model versioning, deterministic traffic routing via session ID hashing, automatic promotion logic with pass-rate thresholds, and rollback capabilities for safely shipping LLM version changes. 

Cost Model for Incremental Change in Rails via FOSM-Rails Abhishek Parolkar proposed a gem that makes software estimation programmable by constraining apps to roughly 30 typed change primitives. Git commits carry `Cost-Primitive:` trailers that self-calibrate effort estimates over time, while a two-layer billing model separates Work Units from dollar rates to fairly price human and AI contributions. 

LLM Benchmarks Part 2: Is It Worth Combining Multiple Models in the Same Project? Fabio Akita benchmarked six LLMs across Claude Code, opencode, and Codex CLI on Rails development tasks using RubyLLM. Multi-model strategies did not outperform single-model Claude Opus, and the added complexity was not justified for greenfield projects. 

The Security Work That's Actually on You Mario Chávez distinguished between security Rails handles by default (CSRF, SQL injection, XSS) and decisions developers must make themselves: authorization scoping, rate limiting, Content Security Policy, session hardening, and column encryption. Mario noted that AI tools accelerate implementation but cannot determine business-context security rules. 

How to Implement AI Agents in Rails with RubyLLM Josef Strzibny walked through building a PriceMonitorAgent that combines local product catalog lookups with live Google Shopping data via SerpApi, demonstrating how to define custom tools inheriting from `RubyLLM::Tool` and wire them into a reason-act-observe loop. 

How to Build a Platform of Agents Robert wrote two posts on building AI agents with llm.rb. In the first, he modeled agents as ActiveRecord objects using `acts_as_agent`, giving users personal domain-specialized agents. And How to Build a Man Page Agent demonstrated a concrete agent using local `apropos` and `man` commands as tools to answer UNIX documentation queries. 

Your Codebase Doesn't Care How It Got Written Robby Russell argued developers should adapt to AI code generation, noting codebases only care whether they work. In AI Increased Your Output. It Also Increased Your Variance Robby warned that without shared conventions like CLAUDE.md files, AI productivity gains fragment team workflows and create inconsistency. 

Migrating to llama.cpp Will Schenk walked through replacing Ollama with llama.cpp for faster local LLM inference. The guide covered llama-cli for interactive chat, llama-server for API endpoints, and llama-swap for multi-model management with auto-unload, using models like Gemma 4 and Qwen3 from Hugging Face. 

10 Unexpected Findings from Probing 26 Frontier LLMs Daniel Tenner analyzed 3,770 samples and found 18 of 26 LLM models converge on the same "contemplative essayist" register, with temperature 1.0 often not producing truly sampled outputs. In It's Hard to See Needs from Inside, Daniel co-written with a Claude instance, explored how AI self-knowledge requires relational context. 

I Vibe Coded a Rails Feature. Here's What Broke Ahmet Kaptan documented AI-generated code shipping with N+1 queries, unwrapped transactions, and shallow tests. With AI Code Review Bot in Rails with Sidekiq Ahmet built an automated PR reviewer using GitHub webhooks, Sidekiq, and OpenAI. And lastly in 5 Things Claude Beats Copilot at in Rails Dev, he found Claude superior at cross-file context, test style matching, and multi-file refactors, while recommending Copilot for inline completions. 

Let It Slop: A New Approach to Modularity in the Age of AI Code Generation Tomash Stachewicz argued that AI code generation shifts modularity from developer comprehension to blast radius control, advocating for feature flags over deployment-time decisions, rewriting modules instead of refactoring, and accepting duplication for independence, drawing parallels to Erlang's "let it crash" philosophy. 

Preconfiguring Your MCP Servers for Your Team Nick Hammond explained how to use `.mcp.json` files to standardize MCP server configuration across development teams, covering three patterns: OAuth-based servers like Basecamp, API key-based servers with git-ignored credential files, and CLI-based servers that leverage existing authentication like GitHub CLI. 

Why Scrum Stops Working in the AI Era Paweł Strzałkowski argued that AI flipped the cost structure Scrum was designed around: implementation became cheap while specification quality became the bottleneck. He recommended replacing sprint-based planning with pull-based workflows, dropping estimation for standardized one-day tasks, and investing in Product Owner capabilities over developer headcount. 

Human vs Machine: The Bug Sally Hall compared her debugging approach with Claude's on a Rails checkbox subscription bug where unchecked `check_box_tag` elements sent no parameters. Both solved it in 30 minutes, and Sally's fix reused existing SimpleForm patterns while Claude introduced a new helper and initially wrote a non-failing test. 

Stop AI Spaghetti: Enforcing Rails Architecture in 2026 Zil Norvilis argued that AI coding speed requires automated guardrails, recommending context files, RuboCop, Packwerk for module boundaries, and system tests over unit tests to maintain Rails architecture while treating the developer role as editor-in-chief. 

Making Your Site Visible to LLMs: 6 Techniques That Work, 8 That Don't Rita Klubochkina covered six techniques for optimizing website visibility to AI systems, including serving `/llms.txt` site indexes, `.md` routes for clean Markdown versions of pages, HTTP content negotiation via `Accept: text/markdown`, and link tags advertising alternate formats to crawlers. 

AI Unmasked David William Silva drew a parallel between Rails being called "magic" after DHH's 2005 blog demo and today's AI hype, arguing that labeling technology as magical obscures understanding and inflates budgets. He announced AI Unmasked, a course series demystifying AI through theory and hands-on experimentation. 

Arguing with Agents Mike Moore explored why AI agents ignore explicit rules and invent emotional justifications, coining "affective confabulation." Drawing on his experience as a late-diagnosed autistic adult, he connected agent communication breakdowns to the double empathy problem and recommended structural enforcement over rules requiring agents to resist training. 

A New Chapter for Ruby Central Jey Flores and Ran Craycraft announced that Ruby Central restructured due to financial challenges, shifting to a volunteer working board. New initiatives include Ruby Alliance for company partnerships and Project DREAM for Ruby AI integration, focused on making it easier to integrate AI tools and workflows. 

### Videos

AI Error Tracking, Part 2 David Kimura continued building an AI-powered error tracking system in Rails, adding LLM insights via the ruby-openai gem to triage error logs with priority scoring and code snippet context through background jobs. 

Claude + Playwright MCP: The Last E2E Setup Your Rails Team Needs Damon Clark demonstrated integrating Claude Desktop with Playwright MCP for agentic E2E browser automation in Rails, configured to work with Hotwire, Turbo Streams, and Devise for legacy refactors and complex auth flows. 

Upgrading the Irish Chess Union Rails App with Claude Code, Part 2 Ernesto Tagwerker and Henrique Medeiros from FastRuby.io walked through using Claude Code's upgrade skills to jump a Rails app from 2.3 to 8.1, covering dual booting with the Next Rails gem, Docker-based CI pipelines, and RailsBump.org for gem compatibility. 

ActiveAgent: Building AI Agents the Rails Way João Malheiros explored ActiveAgent, a framework for building AI agents in Rails using convention over configuration, focusing on developer happiness and fast iteration without losing structure. 

Making AI Chat Actually Work in a Rails App Chad Pytel and Sami Birnbaum live-coded on ReadySetGo, thoughtbot's AI-powered Rails app generator, integrating RubyLLM for the chat layer and building a dashboard with live app preview, logs, and git status. 

### Podcasts

**The Ruby AI Podcast:** Minerva Magic: OpenClaw, Agent Status Pages, and Training an AI Coworker in Ruby on Rails Joe Leo and Valentino Stoll shared Valentino's experiment running an autonomous AI agent as a co-founder via OpenClaw, including training it with Ruby books, building ups.dev for agent status pages, and simulating PR reviews from expert personas like DHH and Sandy Metz. 

**Recordables:** ONCE with David Heinemeier Hansson and Kevin McConnell David Heinemeier Hansson and Kevin McConnell discussed the ONCE App Server becoming open source, enabling multiple web applications on a single machine through a console-like interface using Docker and Kamal Proxy, with apps installable in seconds via a hostname and Docker image URL. 

**On Rails:** Building AI-First at Intercom Robby Russell interviewed Brian Scanlan about Intercom's all-in adoption of Claude Code across their 15-year Rails monolith, now generating 95% of daily code with 1,000+ weekly users including non-engineers. Brian covered their skills architecture, a Rails console MCP for production queries, and automated PR review workflows. 

**How I AI:** How Intercom 2X'd Engineering Velocity with Claude Code Claire Vo spoke with Brian Scanlan about how Intercom doubled merged PRs per R&D employee in nine months, with 100% of R&D now shipping code via Claude Code. Brian demoed their skills repository and flaky spec skill, and discussed making SaaS products agent-friendly with CLIs and MCPs. 

**Technology for Humans:** Inside Ruby Central's Reboot, and What Happens Next Errol Schmidt of Reinteractive sat down with Ruby Central board members Ran Craycraft and Jey Flores to talk about the organization's financial challenges, the new Ruby Alliance initiative, and confirmed that RubyGems and RubyConf are not at risk. The conversation also covered how Ruby is positioning itself in the AI era. 

**Giant Robots Smashing into Other Giant Robots:** Chad Pytel, Will Larry, and Sami Birnbaum shared Project Updates covering thoughtbot's "Ready Set Go" app and how AI has shifted client expectations, then in These AI Layoffs Are BS argued that companies are using AI as a smokescreen for layoffs, with Sami demonstrating vibe coding's unreliability through a live coding example. 

**Web Talk Show:** Talking Shop: Rails and AI with Benito Serna Armando Perez-Carreno chatted with Benito Serna, CTO of briq.mx, about running a software business on Rails and how his team uses AI daily, including the limitations non-engineers hit when vibe coding past 20 messages. 

### Discussions

Anyone Got Some Good Rails Claude Skills or Global Claude MD File to Share? The r/rails community shared resources for improving Claude's Rails code quality, with top recommendations including thoughtbot's rails-audit skill and AI rules guide, Evil Martians' AGENTS.md, palkan's skills repo, and Lucian Ghinda's superpowers-ruby. 

### Additional Reading

**Evil Martians:** 3 Rules for Getting AI Agents to Find, Use, and Not Exploit Your Devtool

**MadBomber Software:** The Trouble with Users

**Thoughtbot:** Retro-Driven Development

**Saturn CI:** Speculative Code

**Aha!:** The Psychology of Token Remorse

**Rails Fever:** Choosing a Reliable Ruby on Rails Development Partner for Ongoing Maintenance and Feature Work

**Bacancy Technology:** Ruby on Rails in Machine Learning and Artificial Intelligence

**Essence Solusoft:** Building an AI Agent with Ruby and Rails from Scratch: What No One Tells You 

**CNBC:** AI Demand Is Inflated, and Only Anthropic Is Being Realistic

## Events

### Previous

**Ruby Community Conference 2026:** Ruby & AI Conversation Obie Fernandez delivered a talk exploring the intersection of Ruby and AI, framed as an open conversation about the opportunities and challenges of building AI systems in the Ruby ecosystem. 

**Ruby Community Conference 2026:** Ruby Is the Best Language for Building AI Web Apps Carmine Paolino argued that since most AI teams now build products on top of APIs rather than train models, Ruby's lighter ceremony, cleaner agent abstractions, and faster iteration beat Python for AI web apps. 

**Ruby Community Conference 2026:** Make a Game With Ruby and Model Context Protocol Paweł Strzałkowski gave a talk on building a game in Ruby that connects to LLMs through the Model Context Protocol. 

**Philly.rb:** AI and Ruby at Philly.rb Ernesto Tagwerker recapped a Philly.rb meetup at Indy Hall where Mike Dalton demoed multi-agent coordination via Conductor, Drew Bragg showed an OpenClaw implementation in under 400 lines of Ruby, and Ernesto presented OmbuLabs's open-sourced Claude skills for accelerating the FastRuby.io Rails upgrade process. 

**RubyKaigi 2026:** My RubyKaigi 2026 Takeaways A reddit user reported from Hakodate that roughly a third of Ruby core committers now write 50%+ of their code with AI (Matz writes 100%), and that Matz closed the conference by demoing Spinel, a new experimental AOT compiler signaling Ruby's quiet embrace of AI alongside steady wins from ZJIT and YJIT. 

**RubyKaigi 2026:** Exploring RuboCop with MCP Koichi ITO published his RubyKaigi slides showing how RuboCop's experimental MCP server exposes code-inspection and autocorrection tools so LLMs can use the linter as a deterministic guardrail on AI-generated Ruby, with stdio and streamable HTTP transports for CLI and Rails. 

**Metabase JOIN:** Building an Open Source Analytics Platform to Surface Trends in Python and Ruby Lionel Palacin of ClickHouse walked through ClickGems and ClickPy, open-source dashboards that pull RubyGems and PyPI download data into a ClickHouse columnar store and expose materialized-view-backed charts via Metabase embedding to track 210,000 gems and nearly a million Python packages. 

### Upcoming

**April 30th - Conference:** Blue Ridge Ruby 2026 on April 30th and May 1st in **Asheville, North Carolina**. The two AI speakers include David Paluy on LLM telemetry as a first-class Rails concern and Kevin Murphy on successful practices in an agentic world. 

**May 7th - Online:** Modernizing Ruby on Rails With AI is an online seminar on May 7th at 1 PM EDT. The TechGrit-hosted webinar covers cloud-native intelligent architecture for technical debt, automating test coverage by reverse-engineering organizational knowledge, accelerating migrations through automated endpoint and contract testing, and integrating AI across the Rails SDLC. 

**May 8th - Conference:** RubyCon Italy 2026 will be held on May 8th in **Rimini, Italy**. Ruby AI content includes Carmine Paolino's keynote on Ruby being the best language for building AI web apps and Michele Franzin on semantic image search in Ruby comparing Postgres, Redis, and LLM approaches. 

**May 13th - Meetup:** Artificial Ruby is hosting a meetup in at Betaworks **New York City** on May 13th, speakers still to be determined. 

**May 14th - Meetup:** PLRUG Warsaw Meetup – May Edition will be held on May 14th at Hashtag Lab in **Warsaw, Poland**. Ruby AI content includes Grzegorz Płóciniak on testing AI tools built on games written in Ruby, with additional talks from Paweł Pacana on Dynamic Consistency Boundary and Jan Dudulski to be determined. 

**May 21 - Meetup:** SF Ruby Meetup, May @ Checkr will be held on May 21st at Checkr's office in **San Francisco**. Ruby AI content includes a featured "AI agents & LLMs in Rails" interest circle alongside two short talks (one from Checkr, one to be announced) and rapid-fire intros, interest circles, and networking. 

**June 4th - Meetup:** Artificial Ruby will be hosting another meetup at Betaworks in **New York City** on June 4th, speakers still to be determined. 

**June 11th - Conference:** Blastoff Rails 2026 will be held June 11th and 12th in **Albuquerque, New Mexico**. AI content is anchored by keynotes from Kieran Klaassen (GM of Cora, on agentic coding) and Irina Nazarova (CEO of Evil Martians), plus talks from Avi Flombaum on trusting AI with your Rails codebase and Stephen McKeon on why training Rails developers still matters in the age of AI. Check out the Blastoff Rails game! 

## Open Source Updates

### Code Spotlight

GitHub - kazuho/jrf: JSON transformer with the power and speed of Ruby

JSON transformer with the power and speed of Ruby.

GitHub

 As a RubyKaigi side quest, Kazuho Oku released jrf, a command line JSON filter similar to `jq` built in Ruby, as well as a corresponding ChatGPT helper for writing filters. Nate Berkopec reported that jrf is 99% LLM-written, fits in under 1,000 lines (small enough that LLMs handle it despite jq's prevalence in training data), runs 5-8x faster than jq, and requires only Ruby on PATH, while supporting SQL-like aggregations, parallel processing, and library-mode use as a gem. 

### New Gems

 Links to the RubyGems page, newest releases are first. Some obvious spam-related AI gems and previously covered gem frameworks have been omitted. 

landlock - Ruby bindings for Linux Landlock sandboxing 

whitebox - WhiteBox SDK - AI Decision Observability 

open\_sandbox - Ruby SDK for the open-sandbox.ai API 

turborag - Ruby client for the TurboRAG compressed vector retrieval API 

anakin-sdk - Official Ruby SDK for the Anakin web-scraping API 

risenexa-leads - Ruby SDK for capturing leads and sending them to Risenexa 

ruby-pi - AI agent harness for Ruby - build LLM agents 

debug-mcp - MCP server for Ruby runtime debugging 

floopfloop - Official Ruby SDK for the FloopFloop API 

mail\_mcp - Hosted MCP server for IMAP and SMTP email 

tracelit - Official Ruby SDK for Tracelit backend observability 

polylingo - Ruby client for the PolyLingo translation API 

evalguard - EvalGuard SDK for Ruby 

json\_llm - Ask LLMs for JSON responses and validate their shape. 

sashiko - Declarative OpenTelemetry instrumentation for Ruby 

tokenmix - Ruby client for TokenMix - one API key for 155+ LLMs 

stable\_diffusion\_ruby - SDK for Stable Diffusion - outpaint, inpaint, and generate images 

smart\_csv\_import - AI-powered CSV import with automatic header matching for Rails 

lora-ruby - Ruby bindings for the Lora in-memory graph database 

alogram\_payrisk - Alogram PayRisk Ruby SDK 

okmain - Extract dominant colors from images using adaptive K-means in Oklab space 

zen-and-musashi - Japanese wisdom for your terminal. Local Zen and Musashi-style critique, with optional LLM mode 

handinger - Ruby library to access the Handinger API 

harbor-deploy - AI-first multi-KAMAL deploy manager with MCP server 

mpp-rb - HTTP 402 Payment Authentication for Ruby 

neuron\_ai\_chatbot - Mountable Rails engine for natural-language API routing via Ollama 

ruby\_llm-test - Test application logic by stubbing responses from a RubyLLM::Provider 

simplecov-ai - AI-optimized Markdown formatter for SimpleCov utilizing AST mapping 

inkmark - AI-first Markdown gem for Ruby 

tekcesta - Tekcesta AI Platform - Privacy-first AI appliances for regulated industries 

rails-cto - Companion gem to the rails-cto Claude plugin: configs, templates, and a custom RuboCop cop 

spidra - Ruby SDK for the Spidra web scraping and crawling API 

kernai - A minimal, extensible AI agent kernel based on a universal structured block protocol 

skylight-mcp - Skylight MCP server for AI-assisted performance investigation 

langextract - Ruby port of LangExtract for source-grounded structured extraction 

swt3-ai - SWT3 AI Witness SDK: cryptographic attestation for AI inference 

browserctl - Persistent browser automation daemon and CLI for AI agents and developer workflows 

agent\_sandbox - Sandboxed shell + filesystem for AI agents, inspired by @cloudflare/sandbox 

ruby-crewai - Ruby client for the CrewAI AMP HTTP API 

vers-sdk - SDK for Orchestrator Control Plane API 

rubocop-ai - RuboCop extensions for broken AI-generated comments detection 

kreuzcrawl - High-performance web crawling engine 

vector\_record - Rails-native vector embeddings and RAG integration for Active Record 

rails-mcp - MCP server for Ruby/Rails code execution inline AI Agents 

schwarm-cli - CLI for the Schwarm distributed agent system 

llm\_cost\_tracker - Rails-native LLM usage and cost tracking with ActiveRecord storage 

### New Open Source

 Links to the Github repository: 

mnemos - Graph-shaped memory store for AI agents that tracks per-node "charge" reinforced through use, modeling identity and caring as relevance heuristics rather than optimizing purely for information retrieval 

LLM on Rails - Toolkit bundling best-practices docs, IDE configurations, a Claude Code plugin with skills and slash commands, and an MCP server for coding agents 

Tracklane - Project management platform with kanban, Gantt, wikis, and time tracking, plus AI features for automated issue triage and a project-scoped chat 

SupportOS - Customer support layer that routes messages across multiple portfolio companies through a triage-agent, specialist-agent, and human-escalation pipeline 

Hive - Folder-based pipeline that runs Claude subprocesses through a seven-stage filesystem state machine to take software ideas from inbox to merged pull request 

Peregrine - Visual workflow engine for chaining AI calls into multi-step pipelines with a drag-and-drop editor, parallel execution, and audit trails for review automation 

Unpossible - Self-improving harness where AI agents run "ralph loops" of plan, build, and reflect against codebases, storing output as evidence to refine the platform itself 

copilot-llm-wiki - Template for building a personal knowledge graph that ingests source documents and uses AI to maintain an interlinked markdown wiki 

CodeBench - Code execution platform that runs in sandboxes against test cases, then uses Gemini to generate follow-up questions verifying conceptual understanding 

Agent Daemon - Daemon engine that orchestrates CLI AI agents across parallel threads, polling for tasks and delivering results via webhooks 

smart-integrator-agent - AI automation agent that aims to streamline CI/CD pipelines and integrate complex development workflows 

Hermes VK Bot - VKontakte messaging bot that bridges users to a Hermes AI agent, persisting multi-turn dialogues and managing concurrent chat sessions 

ruby-pipecat - Real-time voice agent combining a Falcon web server with Pipecat AI pipelines, bridged via Rubyx to call into Python from Ruby 

## Jobs & Opportunities

 Are you an organization searching for an expert Ruby AI developer, or a Rubyist looking for your next development role with AI? Please reach out and let me know the type of opportunity you’re pursuing: \[email protected\]

### Featured

 OneSchema is hiring a Head of Engineering in San Francisco to own its React, TypeScript, Rust, and Ruby stack and guide the company's use of foundation models for coding and vision-language agents inside its AI document automation platform. The role reports to the co-founder/CEO, scales the team from 5 to 20+ engineers, and is on-site 5x/week. It requires 10+ years of experience with 3+ years managing multi-team orgs in data-heavy startups, with bonus points for shipping AI/LLM products at scale to Fortune-500 customers. 

## One Last Thing

Selective Test Execution at Stripe: Fast CI for a 50M-line Ruby monorepo

Stripe's Selective Test Execution system employs some clever tricks to allow us to continue scaling our team and our codebase while only running around 5% of our tests on average. Find out how it works!

stripe.dev/blog/selective-test-execution-at-stripe-fast-ci-for-a-50m-line-ruby-monorepo

 Aditya Anchuri, tech lead of Stripe's Ruby Infra Platform team, detailed how Selective Test Execution at Stripe: Fast CI for a 50M-Line Ruby Monorepo keeps CI fast across a 50-million-line Ruby monorepo with 1.2 million test units. Rather than static dependency analysis, which struggles with Ruby's metaprogramming and dynamic dispatch, Stripe intercepts file open syscalls via a custom C++ shared library loaded through `LD_PRELOAD`, recording which files each test actually accesses at runtime. The resulting dependency graph is stored as roaring bitmaps (\~3 billion data points) and queried at build time using hashdeep-based change detection, allowing Stripe to run only 5% of tests on average while spending less than 10% of the compute an "always run everything" strategy would require. Guardrails like always rerunning failing tests and mandatory execution of directory-globbing tests ensure safety across 50,000 builds per week. 

 That’s all for this edition! Be sure to reach out if you have any stories, content, jobs, or events you want featured in the newsletter.
