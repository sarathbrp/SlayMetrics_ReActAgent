# RCA Slay Metrics — Claude Code Guidelines

## File Size Limit

- **No file may exceed 300 lines.**
- If a file approaches 300 lines, split it before adding more code:
  - Extract a cohesive class or group of functions into a new `core/` module.
  - Update `core/__init__.py` to export the new module.
  - Prefer splitting by responsibility, not arbitrarily.

## Project Structure

```
agent.py          — RCAAgent (LangGraph graph + main entry point)
core/
  __init__.py     — re-exports all core classes
  config.py       — Config
  ssh.py          — RemoteExecutor
  audit.py        — AuditRunner
  analyzer.py     — RCAAnalyzer (DSPy)
  display.py      — Display (pretty tables)
  report.py       — ReportWriter
prompts/
  rca.md          — DSPy RCA Signature instructions
scripts/
  *.sh            — Audit scripts deployed to DUT
dspy_data/        — DSPy examples + compiled programs (auto-created)
rca_reports/      — Timestamped RCA report output (auto-created)
config.yaml       — SSH target + benchmark config
.env              — LLM credentials (never commit)
```

## Python Standards

### Style
- Follow PEP 8. Max line length: **100 characters**.
- Use double quotes for strings.
- Use f-strings for interpolation; avoid `.format()` or `%`.
- One blank line between methods, two between top-level definitions.

### Typing
- All function signatures must have type annotations (parameters + return type).
- Use `from __future__ import annotations` if forward references are needed.
- Prefer `X | Y` union syntax over `Optional[X]` or `Union[X, Y]`.
- Use `TypedDict` for structured dicts passed between LangGraph nodes.

### Classes
- Use OOP. Each class has a single responsibility.
- Prefer `__init__` dependency injection over module-level globals.
- Use context managers (`__enter__`/`__exit__`) for resources (SSH connections, file handles).
- Keep `__init__` free of side effects — no network calls, no file I/O.

### Error Handling
- Raise specific exceptions, not bare `Exception`.
- Only catch what you can handle. Let unexpected errors propagate.
- Log errors with `logger.error()` before re-raising or returning error state.
- Never silently swallow exceptions.

### Logging
- Use `logging.getLogger("slayMetrics.<module>")` in every module.
- Use `%s` style (not f-strings) in log calls to defer formatting.
- Log level is driven by `config.yaml` `log_level` field.
- Never use `print()` — always use the logger, including for reports and tables.

### Imports
- Standard library first, then third-party, then local — separated by blank lines.
- No wildcard imports (`from x import *`).
- Import classes directly; avoid aliasing unless the name conflicts.

### DSPy
- DSPy Signatures must have a docstring (loaded from `prompts/rca.md`).
- Always call `RCAAnalyzer.configure()` before invoking any DSPy module.
- Save examples after every successful run via `RCAAnalyzer.save_example()`.
- Never hardcode prompt text in Python — keep it in `prompts/`.

### Configuration
- All secrets come from `.env` via `python-dotenv`. Never hardcode credentials.
- All infra config (hosts, ports, paths) comes from `config.yaml` via `Config`.
- No magic strings scattered in code — define constants at the top of the file.

### Git
- Never commit `.env`, `dspy_data/`, or `rca_reports/`.
- Commit messages: imperative mood, under 72 chars (`add DSPy optimizer`, not `added`).
