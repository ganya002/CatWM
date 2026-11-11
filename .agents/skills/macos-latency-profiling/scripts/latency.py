#!/usr/bin/env python3
"""Summarize successful latency and deadline compliance for every attempt."""
import argparse
import csv
import json
import math
from pathlib import Path
import sys


def finite_number(value, label):
    if isinstance(value, bool):
        raise ValueError(f"{label} must be a finite, non-negative number")
    try:
        number = float(value)
    except (ValueError, TypeError):
        raise ValueError(f"{label} must be a finite, non-negative number") from None
    if not math.isfinite(number) or number < 0:
        raise ValueError(f"{label} must be a finite, non-negative number")
    return number


def load_records(paths, format_name="auto"):
    records, seen = [], set()
    for path in paths:
        kind = format_name if format_name != "auto" else ("csv" if path.suffix.lower() == ".csv" else "jsonl")
        with path.open(newline="", encoding="utf-8-sig") as stream:
            if kind == "csv":
                reader = csv.DictReader(stream)
                headers = reader.fieldnames or []
                if len(headers) != len(set(headers)):
                    raise ValueError(f"{path}: duplicate CSV column names")
                source = enumerate(reader, 2)
            else:
                source = ((line, json.loads(text)) for line, text in enumerate(stream, 1) if text.strip())
            for line, record in source:
                location = f"{path}:{line}"
                if not isinstance(record, dict):
                    raise ValueError(f"{location}: expected an object")
                identifier = record.get("request_id")
                if not isinstance(identifier, str) or not identifier.strip():
                    raise ValueError(f"{location}: request_id must be a non-empty string")
                if identifier in seen:
                    raise ValueError(f"{location}: duplicate request_id {identifier!r}")
                seen.add(identifier)
                status = record.get("status")
                if status not in {"ok", "error", "timeout", "cancelled"}:
                    raise ValueError(f"{location}: invalid status {status!r}")
                duration = record.get("duration_ms")
                if duration is None or duration == "":
                    if status == "ok":
                        raise ValueError(f"{location}: a successful request requires duration_ms")
                    record["duration_ms"] = None
                else:
                    record["duration_ms"] = finite_number(duration, f"{location}: duration_ms")
                records.append(record)
    if not records:
        raise ValueError("No measured requests were supplied")
    return records


def nearest_rank(sorted_values, probability):
    if not sorted_values:
        return None
    return sorted_values[max(0, math.ceil(probability * len(sorted_values)) - 1)]


def binomial_cdf(limit, trials, probability):
    """P(X <= limit), using log probabilities to avoid underflow in the tail."""
    if limit < 0:
        return 0.0
    if limit >= trials or probability == 0:
        return 1.0
    if probability == 1:
        return 0.0
    log_p, log_q = math.log(probability), math.log1p(-probability)
    term = trials * log_q
    terms = [term]
    for value in range(limit):
        term += math.log(trials - value) - math.log(value + 1) + log_p - log_q
        terms.append(term)
    peak = max(terms)
    log_sum = peak + math.log(math.fsum(math.exp(term - peak) for term in terms))
    return min(1.0, math.exp(log_sum))


def binomial_survival(hits, trials, probability):
    if hits <= 0:
        return 1.0
    if hits > trials:
        return 0.0
    if hits > trials / 2:
        return binomial_cdf(trials - hits, trials, 1 - probability)
    return max(0.0, 1 - binomial_cdf(hits - 1, trials, probability))


def compliance_lower_bound(hits, trials, confidence):
    """Exact one-sided Clopper-Pearson lower bound, conditional on IID trials."""
    if not 0 <= hits <= trials or trials <= 0 or not 0 < confidence < 1:
        raise ValueError("Invalid binomial confidence-bound parameters")
    if hits == 0:
        return 0.0
    alpha = 1 - confidence
    if hits == trials:
        return math.exp(math.log(alpha) / trials)
    low, high = 0.0, hits / trials
    for _ in range(64):
        midpoint = (low + high) / 2
        if binomial_survival(hits, trials, midpoint) < alpha:
            low = midpoint
        else:
            high = midpoint
    return (low + high) / 2


def summarize(records, threshold=None, required_fraction=0.99, confidence=0.95, assume_iid=False):
    counts = {status: sum(row["status"] == status for row in records)
              for status in ("ok", "error", "timeout", "cancelled")}
    values = sorted(row["duration_ms"] for row in records if row["status"] == "ok")
    count = len(values)
    warnings = []
    if count < 1000:
        warnings.append("The successful p99 estimate has few tail observations; inspect sample count and uncertainty.")
    if counts["ok"] != len(records):
        warnings.append("Latency percentiles are conditional on success. Failed attempts remain in deadline compliance.")
    result = {
        "attempts": len(records), "statuses": counts, "success_fraction": counts["ok"] / len(records),
        "successful_latency_ms": {
            "count": count, "min": values[0] if values else None,
            "p50": nearest_rank(values, 0.5), "p95": nearest_rank(values, 0.95),
            "p99": nearest_rank(values, 0.99), "max": values[-1] if values else None,
            "observations_at_or_above_p99_rank": count - math.ceil(0.99 * count) + 1 if count else 0,
            "estimator": "nearest_rank", "scope": "successful_requests_only",
        }, "warnings": warnings,
    }
    if threshold is not None:
        hits = sum(row["status"] == "ok" and row["duration_ms"] < threshold for row in records)
        lower = compliance_lower_bound(hits, len(records), confidence) if assume_iid else None
        result["deadline_compliance"] = {
            "threshold_ms": threshold, "comparison": "strictly_less_than", "hits": hits,
            "misses": len(records) - hits, "observed_fraction": hits / len(records),
            "required_fraction": required_fraction, "confidence": confidence if assume_iid else None,
            "one_sided_lower_bound": lower,
            "method": "clopper_pearson_one_sided" if assume_iid else None,
            "iid_assumed_by_caller": assume_iid,
            "conclusion": ("supported_under_iid_assumption" if lower >= required_fraction else
                           "not_supported_at_requested_confidence") if lower is not None else "descriptive_only",
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--format", choices=["auto", "csv", "jsonl"], default="auto")
    parser.add_argument("--endpoint", required=True, help="Name of the measured request-to-completion boundary")
    parser.add_argument("--group-by", default="", help="Comma-separated fields, such as build,scenario")
    parser.add_argument("--threshold-ms", type=float)
    parser.add_argument("--required-fraction", type=float, default=0.99)
    parser.add_argument("--confidence", type=float, default=0.95)
    parser.add_argument("--assume-iid", action="store_true", help="Enable a confidence bound conditional on IID requests")
    args = parser.parse_args()
    try:
        if not args.endpoint.strip():
            raise ValueError("endpoint must not be empty")
        if not 0 < args.required_fraction < 1 or not 0 < args.confidence < 1:
            raise ValueError("required-fraction and confidence must be between 0 and 1")
        if args.threshold_ms is not None and (not math.isfinite(args.threshold_ms) or args.threshold_ms <= 0):
            raise ValueError("threshold-ms must be finite and greater than 0")
        records = load_records(args.inputs, args.format)
        fields = [field.strip() for field in args.group_by.split(",") if field.strip()]
        if len(fields) != len(set(fields)):
            raise ValueError("group-by fields must be unique")
        groups = {}
        for record in records:
            if any(field not in record or record[field] in (None, "") for field in fields):
                raise ValueError(f"Request {record['request_id']!r} lacks a group-by field")
            key = tuple(str(record[field]) for field in fields)
            groups.setdefault(key, []).append(record)
        output = {"endpoint": args.endpoint, "units": "milliseconds", "inputs": [str(p) for p in args.inputs],
                  "confidence_scope": "per_group; no multiple-comparison correction", "groups": []}
        for key, rows in groups.items():
            output["groups"].append({"group": dict(zip(fields, key)), **summarize(
                rows, args.threshold_ms, args.required_fraction, args.confidence, args.assume_iid)})
        print(json.dumps(output, indent=2, allow_nan=False))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
