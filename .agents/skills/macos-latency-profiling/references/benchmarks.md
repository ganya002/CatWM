# Tail-latency evidence

## Input contract

The analyzer accepts CSV or JSONL. Each row represents one request after the defined start event. Required fields are `request_id` and `status`. Successful requests also require `duration_ms`. IDs must be unique within the complete input. Valid statuses are `ok`, `error`, `timeout`, and `cancelled`.

For `ok`, `duration_ms` records the finite, non-negative elapsed time to the declared readiness condition. For other statuses, the duration may be absent. A supplied failure duration records time until failure or observation timeout. It is not a successful readiness latency. The original rows remain the authoritative record.

```json
{"request_id":"a-001","status":"ok","duration_ms":1.7,"build":"before","scenario":"warm"}
{"request_id":"a-002","status":"timeout","duration_ms":1000,"build":"before","scenario":"warm"}
```

```sh
python3 scripts/latency.py samples.jsonl --endpoint request-to-ready --group-by build,scenario --threshold-ms 2
python3 scripts/latency.py samples.csv --endpoint request-to-ready --threshold-ms 2 --required-fraction 0.99 --assume-iid
```

`--endpoint` names the measured boundary. The script cannot verify its meaning. Trace or code evidence must establish that meaning. Use grouping when builds, scenarios, or endpoints differ. Do not pool creation-call duration with complete request or presentation latency.

## Interpret the output

Percentiles use the nearest-rank estimator: sorted successful samples at index `ceil(p*n)-1`. These are explicitly conditional on successful requests. The analyzer reports failures separately and retains them in the denominator for deadline compliance.

Deadline compliance counts a hit only when the request succeeds and its duration is strictly below the threshold. All errors, timeouts, cancellations, and slow successful requests are misses. This is conservative for censored timeouts. Select the intended cancellation policy in the workload definition before collection. Do not remove cancellations after seeing results.

Without `--assume-iid`, the output describes the observed sample and makes no population confidence claim. With that flag, the analyzer calculates an exact one-sided Clopper–Pearson lower confidence bound on deadline compliance. For confidence `c`, it finds `L` such that `P(Binomial(n,L) >= hits) = 1-c`. If every request is a hit, `L = (1-c)^(1/n)`.

Exit status zero indicates valid input and completed analysis. Read `deadline_compliance.conclusion` to assess the target. The process exit status does not encode target achievement.

The bound supports the stated deadline fraction only under independent, identically distributed requests from the workload of interest. Repeated requests in one burst can be correlated. A fast isolated probe can also sample a different distribution from real app use. Inspect ordering, run multiple independent sessions, and retain workload context. Do not label the bound as a confidence interval for p99 latency in milliseconds.

For example, 299 independent requests with no misses support at least 99% deadline compliance at 95% one-sided confidence. This is a statistical statement, not a guarantee for every request or a recommendation to stop at 299 samples. Tail diagnosis often needs many more samples and multiple sessions.

## Collection and comparison

Record all measured attempts. Keep timeouts and failures. Do not trim outliers or discard startup requests to improve a headline. If startup and steady-state requests are separate product requirements, label them before collection and report both.

Record the build hash, OS build, hardware/display configuration, instrumentation, workload, and external interference. Keep raw samples in order. Use matched workloads and alternate builds when feasible to reduce time-dependent bias. Avoid overlapping Desktop tests. Measure the actual product entry point before claiming a complete request improvement from an isolated native benchmark.

A percentile needs uncertainty and sample context. A maximum from a short run is not a stable p99 estimate. Report the number of tail observations, confidence assumptions, failure rate, and any incomplete measurement coverage. Phase percentiles cannot be summed to produce an end-to-end percentile.
