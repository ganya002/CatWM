# Capture and attribute latency

Use `xcrun xctrace list templates`, `xcrun xctrace help record`, and `xcrun xctrace help export` as the installed CLI reference. Templates, instruments, and exported schemas can change with Xcode.

## Capture

Use `scripts/trace.py record` with an exact PID and a bounded duration. The script records target identity, the command, OS/Xcode versions, and exit state beside the trace. It refuses to overwrite existing artifacts. It never relaunches the target or runs a reproduction action.

The optional `--no-prompt` flag passes xctrace's noninteractive option. It does not change OS permissions.

Time Profiler helps identify CPU work and call stacks. System Trace helps distinguish running, runnable, blocked, and waiting time. Choose the capture for the question. For a suspected cross-process wait, an authorized all-process capture can expose the service and scheduler activity that an attached CPU profile omits.

```sh
python3 scripts/trace.py record --pid 1234 --seconds 10 --template 'System Trace' --output /tmp/latency/system.trace
python3 scripts/trace.py record --all-processes --seconds 10 --template 'System Trace' --output /tmp/latency/services.trace
python3 scripts/trace.py toc /tmp/latency/system.trace --output /tmp/latency/toc.xml
python3 scripts/trace.py export /tmp/latency/system.trace --xpath 'XPATH_FROM_THIS_TRACE_TOC' --output /tmp/latency/events.xml
```

Inspect the table of contents before choosing an XPath. Do not assume a schema name or run number from another trace. If command-line exports lack the needed detail, inspect the trace in Instruments when the task permits opening it. Report missing symbolication or permissions. Do not change system profiling permissions, disable protections, or repeatedly retry a rejected capture without authorization.

## Attribution

Place signpost intervals around request receipt, queue entry/exit, native submission/return, readiness observation, and complete response. Keep request IDs stable. Measure instrumentation overhead. Avoid logging large payloads in timed intervals.

For each slow request, account for wall time:

- Running: identify expensive stacks, allocation, serialization, repeated queries, and synchronous I/O.
- Runnable but not running: inspect scheduling delay, QoS, contention, and CPU load.
- Blocked: inspect the wait stack and its duration. `mach_msg` can indicate an IPC wait, but does not identify the server-side cause by itself.
- Awaiting an asynchronous postcondition: observe when the required state becomes true, independently of the submission return where feasible.

Correlate the same request with service activity when the trace exposes that relationship. Otherwise label the service attribution as a hypothesis. Process-wide busy time is not proof of causation for a specific request.

An observed completion time is an upper bound that includes observer delay. A poll can miss an earlier transition. A synchronous reply can precede or follow the externally observable state. Record these boundaries rather than treating any timestamp as physical ground truth.

Preserve the original trace and raw request samples. Use an untraced run for the final latency comparison when capture overhead is material.
