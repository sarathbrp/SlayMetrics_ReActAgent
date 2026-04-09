import logging
import re

logger = logging.getLogger("slayMetrics.evaluator")

_WORKLOAD_RE = re.compile(r"\[\d+/\d+\]\s+(\w+):")
_RPS_RE      = re.compile(r"rps=([\d.]+)")

# Workloads that must improve by >= threshold to keep a fix.
# All other workloads must not degrade (improvement >= 0%).
PRIORITY_WORKLOADS = {"homepage", "small"}


class Evaluator:
    """Parses benchmark output and compares RPS against a baseline."""

    @staticmethod
    def parse_rps(benchmark_output: str) -> dict[str, float]:
        """Extract per-workload RPS from benchmark output."""
        result: dict[str, float] = {}
        current_workload: str | None = None

        for line in benchmark_output.splitlines():
            m = _WORKLOAD_RE.search(line)
            if m:
                current_workload = m.group(1)
                continue
            rps_m = _RPS_RE.search(line)
            if rps_m and current_workload:
                result[current_workload] = float(rps_m.group(1))
                current_workload = None

        return result

    @staticmethod
    def improvement_pct(baseline: dict[str, float],
                        current: dict[str, float]) -> float:
        """Average improvement % across workloads common to both runs."""
        common = set(baseline) & set(current)
        if not baseline or not common:
            return 0.0
        pcts = [
            (current[w] - baseline[w]) / baseline[w] * 100
            for w in common
        ]
        return sum(pcts) / len(pcts)

    @staticmethod
    def should_keep(baseline: dict[str, float], current: dict[str, float],
                    threshold: float,
                    degradation_tolerance: float = -3.0) -> tuple[bool, float]:
        """Keep a fix only if priority workloads improve >= threshold
        AND no other workload degrades.

        Returns (keep, priority_improvement_pct).
        """
        common = set(baseline) & set(current)
        deltas = {
            w: (current[w] - baseline[w]) / baseline[w] * 100
            for w in common if baseline[w]
        }

        priority = {w: d for w, d in deltas.items() if w in PRIORITY_WORKLOADS}
        others   = {w: d for w, d in deltas.items() if w not in PRIORITY_WORKLOADS}

        priority_avg = sum(priority.values()) / len(priority) if priority else 0.0
        degraded     = {w: d for w, d in others.items()
                       if d < degradation_tolerance}

        keep = priority_avg >= threshold and not degraded

        if degraded:
            logger.info(
                "Priority improvement: %.2f%% — ROLLBACK (degraded: %s)",
                priority_avg,
                ", ".join(f"{w}={d:.1f}%" for w, d in degraded.items()),
            )
        else:
            logger.info(
                "Priority improvement: %.2f%% (threshold: %.1f%%) — %s",
                priority_avg, threshold, "KEEP" if keep else "ROLLBACK",
            )
        return keep, priority_avg
