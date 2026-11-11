# Native Desktop probes

Follow the project's live-test instructions and existing user authorization. Creating this skill does not authorize a focus-taking test. Use a read-only inspection or an inactive probe when it can answer the question.

Before mutation, inspect live processes and other test owners. A completed thread can leave a live background driver. Check the process command and identity, not just a PID from an old log. An idle counter or lock file alone does not establish exclusive access. Do not interrupt another test or send messages to another thread without authorization.

An inactive probe should create only its own temporary objects. Record existing Space IDs, the current Desktop per display, relevant window membership, frames, focus, and running app identity. Record any config or persisted state the probe touches. Preserve the current feature build. Inspect build and packaging scripts before using them. A rebuild script can stop the running app.

Use a listen-only input monitor when physical input would invalidate the test. If input resumes, stop further focus or Desktop transitions. Remove only probe-owned inactive objects after checking occupancy. Never restore a stale user-window snapshot over newer user activity.

For a new private API route:

1. Check the installed symbol, selector, and ABI with read-only inspection.
2. Establish a cleanup route for every created object, including one that never enters the normal Desktop catalog.
3. Run one bounded probe before repeated timing runs.
4. Check actual type, display, order, membership, transforms, and the required readiness state. Check animation and presentation separately when they are part of the requested behaviour.

An accepted asynchronous operation can be a no-op. A registered Space can still lack required background or menu resources. A hidden system Space is not automatically interchangeable with a normal Desktop. Reserving an extra normal Desktop changes the visible Desktop list. Check that this fits the user's requirements before adopting it.

Use the project's recovery guard or journal for operations that can leave transforms, hidden windows, or focus changes after a crash. If a probe times out, inspect its exact process and surviving objects before retrying. Do not start a duplicate driver because an observation call expired.

After the probe, audit cleanup and all state that it could change. Record a failed audit as a failed experiment. Do not silently repair unrelated changes from another test, overwrite the user's newer state, or count cleanup time as evidence of creation latency.
