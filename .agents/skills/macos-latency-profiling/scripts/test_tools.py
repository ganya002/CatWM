#!/usr/bin/env python3
"""Exercise statistical invariants and CLI boundaries without Desktop changes."""
import itertools
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import latency

HERE = Path(__file__).resolve().parent


def requests(count, duration=1.0):
    return [{"request_id": str(i), "status": "ok", "duration_ms": duration} for i in range(count)]


class StatisticsTests(unittest.TestCase):
    def test_tail_probability_matches_enumerated_outcomes(self):
        for n in range(1, 8):
            for probability in [0.01, 0.2, 0.5, 0.8, 0.99]:
                outcomes = [(sum(bits), probability ** sum(bits) * (1 - probability) ** (n - sum(bits)))
                            for bits in itertools.product([0, 1], repeat=n)]
                for hits in range(n + 1):
                    expected = math.fsum(weight for count, weight in outcomes if count >= hits)
                    self.assertAlmostEqual(latency.binomial_survival(hits, n, probability), expected, places=12)

    def test_confidence_bound_inverts_binomial_tail(self):
        for n, hits in [(10, 1), (10, 5), (100, 90), (1000, 990), (1000, 999)]:
            bound = latency.compliance_lower_bound(hits, n, 0.95)
            expected = math.fsum(math.comb(n, k) * bound ** k * (1 - bound) ** (n - k)
                                 for k in range(hits, n + 1))
            self.assertAlmostEqual(expected, 0.05, places=10)

    def test_all_hit_closed_form_and_small_sample_uncertainty(self):
        for n in [1, 12, 298, 299, 100000]:
            self.assertAlmostEqual(latency.compliance_lower_bound(n, n, 0.95), 0.05 ** (1 / n), places=14)
        low = latency.summarize(requests(298), 2, assume_iid=True)
        high = latency.summarize(requests(299), 2, assume_iid=True)
        self.assertEqual(low["deadline_compliance"]["conclusion"], "not_supported_at_requested_confidence")
        self.assertEqual(high["deadline_compliance"]["conclusion"], "supported_under_iid_assumption")

    def test_failures_and_threshold_equality_are_misses(self):
        rows = requests(90)
        rows += [{"request_id": f"timeout-{i}", "status": "timeout", "duration_ms": 1000} for i in range(10)]
        rows += [{"request_id": "boundary", "status": "ok", "duration_ms": 2.0}]
        report = latency.summarize(rows, 2, assume_iid=True)
        self.assertEqual(report["successful_latency_ms"]["count"], 91)
        self.assertEqual(report["attempts"], 101)
        self.assertEqual(report["deadline_compliance"]["hits"], 90)
        self.assertEqual(report["deadline_compliance"]["misses"], 11)
        self.assertEqual(report["deadline_compliance"]["conclusion"], "not_supported_at_requested_confidence")

    def test_no_confidence_claim_without_independence_assumption(self):
        report = latency.summarize(requests(1000), 2)
        self.assertIsNone(report["deadline_compliance"]["one_sided_lower_bound"])
        self.assertEqual(report["deadline_compliance"]["conclusion"], "descriptive_only")

    def test_percentile_retains_outliers_and_zero_is_valid(self):
        rows = requests(98, 0) + requests(2, 10000)
        report = latency.summarize(rows)
        self.assertEqual(report["successful_latency_ms"]["min"], 0)
        self.assertEqual(report["successful_latency_ms"]["p99"], 10000)

    def test_all_failed_requests_have_no_success_latency(self):
        report = latency.summarize([{"request_id": "a", "status": "error", "duration_ms": None}], 2, assume_iid=True)
        self.assertIsNone(report["successful_latency_ms"]["p99"])
        self.assertEqual(report["deadline_compliance"]["one_sided_lower_bound"], 0)


class InputTests(unittest.TestCase):
    def test_invalid_records_are_rejected(self):
        bad_inputs = [
            [], [{"request_id": "a", "status": "ok"}],
            [{"request_id": "a", "status": "ok", "duration_ms": float("nan")}],
            [{"request_id": "a", "status": "ok", "duration_ms": True}],
            [{"request_id": "a", "status": "ok", "duration_ms": -1}],
            [{"request_id": "a", "status": "typo", "duration_ms": 1}],
            [{"request_id": "a", "status": "ok", "duration_ms": 1}] * 2,
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "samples.jsonl"
            for rows in bad_inputs:
                path.write_text("\n".join(json.dumps(row) for row in rows))
                with self.assertRaises(ValueError):
                    latency.load_records([path])

    def test_cli_groups_all_attempts_and_emits_valid_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "samples.csv"
            path.write_text("request_id,status,duration_ms,build\na,ok,1,before\nb,timeout,100,before\nc,ok,0.5,after\nd,cancelled,,after\n")
            result = subprocess.run([sys.executable, str(HERE / "latency.py"), str(path), "--endpoint", "request-to-ready",
                                     "--group-by", "build", "--threshold-ms", "2"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual([group["attempts"] for group in report["groups"]], [2, 2])
            self.assertEqual([group["deadline_compliance"]["misses"] for group in report["groups"]], [1, 1])

    def test_duplicate_csv_headers_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "samples.csv"
            path.write_text("request_id,status,duration_ms,duration_ms\na,ok,1,999\n")
            with self.assertRaises(ValueError):
                latency.load_records([path])


class TraceTests(unittest.TestCase):
    def test_dry_run_keeps_arguments_literal_and_creates_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "not-created" / "trace with spaces.trace"
            result = subprocess.run([sys.executable, str(HERE / "trace.py"), "record", "--pid", "1234", "--seconds", "2",
                                     "--template", "System Trace", "--output", str(path), "--dry-run"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            command = json.loads(result.stdout)["command"]
            self.assertIn("System Trace", command)
            self.assertIn(str(path), command)
            self.assertEqual(command[-2:], ["--attach", "1234"])
            self.assertFalse(path.parent.exists())

    def test_overwrite_and_invalid_capture_requests_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "existing.trace"
            path.mkdir()
            for extra in [["--pid", "1234", "--seconds", "1"], ["--pid", "0", "--seconds", "1"],
                          ["--all-processes", "--seconds", "nan"], ["--launch", "app", "--seconds", "1"]]:
                result = subprocess.run([sys.executable, str(HERE / "trace.py"), "record", *extra,
                                         "--output", str(path), "--dry-run"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
            self.assertTrue(path.is_dir())


if __name__ == "__main__":
    unittest.main()
