---
name: macos-latency-profiling
description: Investigate macOS interaction latency and p95/p99 regressions with Instruments traces, native API probes, and repeatable benchmarks.
---

# macOS Latency Profiling

Attribute latency from request receipt to the user's required completion state. Preserve the product's behaviour and recovery requirements.

## Establish the measurement

Read the applicable project instructions and inspect the current implementation and running process. Define the start, completion condition, units, workload, and target percentile before a probe. Distinguish API return, state registration, readiness for use, and visible presentation. Do not substitute one endpoint for another.

Use monotonic timestamps and request IDs across phases. Document clock conversion when an observer uses another clock. Include queueing before native execution and bookkeeping after it in the complete request measurement. Do not add phase percentiles to estimate the complete request percentile.

Start with existing logs and one bounded reproduction. Use a system trace when an opaque native call or wait dominates. Read [trace-reading.md](references/trace-reading.md) for capture and attribution. A Time Profiler sample alone cannot measure time spent blocked.

## Reusable tools

Resolve the script paths relative to this skill directory. All tools use the Python standard library.

```sh
python3 scripts/trace.py templates
python3 scripts/trace.py record --pid 1234 --seconds 10 --template 'Time Profiler' --output /tmp/latency/run.trace --dry-run
python3 scripts/trace.py toc /tmp/latency/run.trace --output /tmp/latency/toc.xml
python3 scripts/latency.py samples.jsonl --endpoint request-to-desktop-ready --threshold-ms 2
```

Remove `--dry-run` only when the capture is within the authorized task scope. Trace capture attaches to an existing process. It does not start or restart the target or control its UI. Use `--all-processes` when cross-process attribution is necessary and within scope.

Read [benchmarks.md](references/benchmarks.md) before collecting a percentile benchmark or interpreting its output. The analyzer retains failed attempts in deadline compliance. Its latency percentiles describe successful requests only. `--assume-iid` enables an exact, one-sided confidence bound on deadline compliance. It does not establish independence.

## Native API and Desktop work

Read [native-desktops.md](references/native-desktops.md) before a probe that changes Spaces, window membership, transforms, or focus. Reuse a tested project harness where possible. Check live test processes as well as thread state. A thread can finish while its background test still runs. A lock protects only tests that honour that lock.

For private APIs, check the ABI and installed implementation before invocation. A resolved symbol can be a no-op. A successful submission does not prove a state change. Check the authoritative postcondition on the exact temporary object. Record the OS build and capability failures. Prefer a read-only inspection when it can reject a route without mutation.

Keep traces, raw samples, build hashes, and temporary probes outside the repository. Keep permanent project tooling in the repository when it belongs to the requested change. Do not replace the user's running build with a different feature snapshot to simplify a comparison.

## Change and verification

State the causal hypothesis and the evidence that would reject it. Change one cost at a time. Follow project-specific retry and stopping rules. Compare equivalent workloads and process states. Keep diagnostic captures separate from low-overhead benchmark runs, and check observer overhead when it can affect the result.

Check complete request latency, failed requests, visual behaviour, cleanup, and recovery as applicable. Report sample count, success rate, p50/p95/p99, endpoint, and uncertainty. Identify measured causes separately from hypotheses.

A few samples above a target do not establish an immutable OS or hardware limit. Reject an unsupported route without claiming that all possible implementations are impossible. If the target remains unmet, state the remaining gap and the next evidence needed. Do not redefine completion around a faster internal phase.
