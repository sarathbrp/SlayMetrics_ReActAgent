# SlayMetrics — Autonomous RCA & Remediation Agent

A LangGraph + DSPy agent that autonomously diagnoses and fixes NGINX performance bottlenecks on a remote DUT (Device Under Test). It runs an audit, generates an LLM-powered Root Cause Analysis, applies fixes in a benchmark-gated loop, and learns from each run.

---

## Architecture

```
deploy_and_run → run_benchmark → analyze → parse_fixes → remediate_fix ─┐
                                                               ↑          │ more fixes
                                                               └──────────┘
                                                               ↓ done
                                                              END
```

**Two LLM calls per run:**
1. `analyze` — sends audit output + benchmark results + similar past cases → RCA report
2. `parse_fixes` — sends RCA report + past history → structured fix JSON

All fix execution is plain Python + SSH — no LLM in the remediation loop.

---

## Features

- **5-group audit** via `omega_master_audit.sh` — hardware, kernel, systemd, nginx, network chaos
- **Scoped remediation tools** — LLM can only call pre-defined tools (no arbitrary shell)
- **Benchmark-gated loop** — each fix is benchmarked; kept only if priority workloads improve
- **Rollback** — every tool stores original state and restores on rejection or Ctrl+C
- **Network chaos tools** — detects and removes TC shaping, iptables connlimit, nftables rate limits
- **Semantic memory** — ChromaDB stores past run outcomes; injected into future LLM prompts
- **DSPy optimization** — BootstrapFewShot compiles better prompts after 30+ examples
- **Session IDs** — every run gets a UUID; reports and DB entries are traceable

---

## Tool Registry

| Tool | What it fixes |
|------|--------------|
| `sysctl` | Kernel network parameters (somaxconn, tcp buffers, conntrack, etc.) |
| `systemd_property` | nginx.service cgroup limits (LimitNOFILE, CPUQuota) |
| `nginx_directive` | nginx config directives (worker_connections, access_log, etc.) |
| `nginx_listen_backlog` | TCP listen backlog on nginx listen lines |
| `cpu_governor` | CPU frequency scaling governor |
| `tc_shaping` | Removes HTB qdisc bandwidth throttle from NIC |
| `iptables_connlimit` | Removes iptables connlimit DROP rules on port 80 |
| `nftables_ratelimit` | Flushes nftables rate-limit rules on port 80 |

---

## Evaluation Logic

- **Priority workloads** (`homepage`, `small`): average improvement must be ≥ threshold
- **Other workloads** (`medium`, `large`, `mixed`): degradation must not exceed tolerance
- **Network tools**: auto-accepted after apply — no benchmark (removing a 25× throttle is always good)
- Both thresholds are configurable in `config.yaml`

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

# Configure credentials
cp .env.example .env   # add GPT_OSS_BASE_URL, GPT_OSS_API_KEY, GPT_OSS_MODEL

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
