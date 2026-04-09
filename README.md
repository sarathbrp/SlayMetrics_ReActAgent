# SlayMetrics — Autonomous RCA & Remediation Agent

A LangGraph + DSPy agent that autonomously diagnoses and fixes NGINX performance bottlenecks on a remote DUT (Device Under Test). It runs an audit, benchmarks with live runtime sampling, generates an LLM-powered Root Cause Analysis, applies fixes in a benchmark-gated loop, and learns from each run.

---

## Architecture

```
deploy_and_run → run_benchmark ─── live sampler (background thread) ───┐
                      ↓                                                 ↓
                 analyze (Call 1: static audit + live hypothesis → RCA report)
                      ↓
                 parse_fixes (Call 2: RCA report + history → structured fixes)
                      ↓
                 remediate_fix ─────────────────────────────────────────┐
                      ↑                               more fixes?        │
                      └────────────────────────────────────────────────┘
                      ↓ done
                     END
```

**Two LLM calls per run:**
1. `analyze` — static audit + benchmark RPS + **live runtime hypothesis** + similar past cases → RCA report
2. `parse_fixes` — RCA report + past history → structured fix JSON

All fix execution is plain Python + SSH — no LLM in the remediation loop.

---

## Features

- **5-group static audit** via `omega_master_audit.sh` — hardware, kernel, systemd, nginx, network chaos
- **Live runtime sampler** — background thread collects 25 samples during benchmark (TCP state, NIC discards, softirq, cgroup throttle, CPU); analyzed into compact hypothesis via pandas
- **Scoped remediation tools** — LLM can only call pre-defined tools (no arbitrary shell)
- **Benchmark-gated loop** — each fix benchmarked; kept only if priority workloads (`homepage`, `small`) improve
- **Network chaos tools** — auto-detected and auto-accepted (TC shaping, iptables connlimit, nftables rate limits)
- **Rollback** — every tool stores original state; restored on rejection or Ctrl+C
- **Semantic memory** — ChromaDB (local `all-MiniLM-L6-v2` embeddings) stores past outcomes; injected into both LLM calls
- **DSPy optimization** — BootstrapFewShot compiles better prompts after 30+ examples
- **Session IDs** — every run gets a UUID; reports, CSV, and DB entries all linked

---

## Tool Registry

| Tool | Scope | What it fixes |
|------|-------|--------------|
| `sysctl` | always | Kernel network parameters (somaxconn, tcp buffers, conntrack, etc.) |
| `systemd_property` | always | nginx.service cgroup limits (LimitNOFILE, CPUQuota) |
| `nginx_directive` | always | nginx config directives (worker_connections, access_log, etc.) |
| `nginx_listen_backlog` | always | TCP listen backlog on nginx listen lines |
| `cpu_governor` | always | CPU frequency scaling governor |
| `tc_shaping` | configurable | Removes HTB qdisc bandwidth throttle from NIC — **auto-accepted** |
| `iptables_connlimit` | configurable | Removes iptables connlimit DROP rules on port 80 — **auto-accepted** |
| `nftables_ratelimit` | configurable | Flushes nftables rate-limit rules on port 80 — **auto-accepted** |

Network tools support `none | read | write` scope in `config.yaml`. Auto-accepted tools skip benchmarking — removing a 25× bandwidth throttle is always correct.

---

## Evaluation Logic

- **Priority workloads** (`homepage`, `small`): average improvement must be ≥ threshold
- **Other workloads** (`medium`, `large`, `mixed`): degradation must not exceed tolerance (noise floor)
- **Network tools**: auto-accepted after `apply()` — no benchmark needed
- All thresholds configurable in `config.yaml`

---

## Live Runtime Sampling

While the benchmark runs (~1–5 min), a background thread SSHes to the DUT and collects metrics every 2 seconds:

| Metric | Signal |
|--------|--------|
| `/proc/net/softnet_stat` | Softirq budget exhaustion, packet drops |
| `ethtool -S <iface>` | NIC rx_discards, rx_errors at ring level |
| `/proc/net/sockstat` | TCP TIME_WAIT, ESTABLISHED, memory pages |
| `vmstat` | CPU us/sy/wa, context switches |
| `cgroup cpu.stat` | CPUQuota throttle ratio during benchmark |

Samples saved to `rca_reports/<session-id>/live_samples.csv`. Pandas analysis computes deltas (cumulative counters), peaks (instant metrics), and trends (monotonic growth detection). A compact ~15-line hypothesis is printed to console and injected into the RCA prompt.

---

## Configuration

```yaml
remediation:
  improvement_threshold_pct: -0.2   # reject only if priority workloads degrade > 0.2%
  degradation_tolerance_pct: -5.0   # non-priority workloads noise floor
  max_fixes: 15
  network_tools:
    tc_shaping: write               # none | read | write
    iptables_connlimit: write
    nftables_ratelimit: write

benchmark:
  collect_live_audit: true
  live_sampling:
    enabled: true
    interval_seconds: 2             # sample every N seconds
    max_samples: 25                 # downsample before analysis (handles long benchmarks)
  final_benchmark_duration_minutes: 5

memory:
  inject_into_rca_analysis: true    # pass similar cases to Call 1
  inject_into_fix_extraction: true  # pass similar cases to Call 2

optimization:
  min_new_examples: 30              # trigger DSPy BootstrapFewShot after N examples
  max_bootstrap_demos: 3
```

---

## Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Configure credentials (.env on DUT/agent machine — never committed)
# GPT_OSS_BASE_URL, GPT_OSS_API_KEY, GPT_OSS_MODEL

# Configure target DUT in config.yaml
# target.host, target.user, target.private_key_path

# Run
python agent.py
```

---

## Output

Each run produces a session folder:
```
rca_reports/<session-uuid>/
  rca_report.md          # LLM diagnosis
  live_samples.csv       # raw runtime samples (25+ rows of metrics)
  final_benchmark.txt    # extended benchmark (if fixes were accepted)

dspy_data/
  examples.jsonl         # training examples (audit → RCA → outcomes)
  rca_program/           # compiled DSPy program (after 30+ examples)
  chroma/                # ChromaDB semantic memory store
```

---

## Scripts

```bash
# View / clean semantic memory
python scripts/clean_chromadb.py
python scripts/clean_chromadb.py --reset
python scripts/clean_chromadb.py --before 2026-04-09
```
