
const MAX_BYTES = 4 * 1024 * 1024
const MAX_FILES = 6
const MAX_FILE_CHARS = 40000

export default {
  async fetch(req, env) {
    const url = new URL(req.url)
    if (req.method !== "POST" || !["/report", "/perf"].includes(url.pathname)) return json({ error: "not found" }, 404)

    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: req.headers.get("cf-connecting-ip") ?? "unknown" })
      if (!success) return json({ error: "too many reports" }, 429)
    }
    if (url.pathname === "/perf") return perf(req, env)
    const length = req.headers.get("content-length")
    if (length === null) return json({ error: "length required" }, 411)
    if (Number(length) > MAX_BYTES) return json({ error: "too large" }, 413)

    let form
    try {
      form = await req.formData()
    } catch {
      return json({ error: "bad form" }, 400)
    }
    const title = clip(String(form.get("title") ?? ""), 120).trim() || "Bug report"
    const body = clip(String(form.get("body") ?? ""), 20000).trim()
    const version = clip(String(form.get("version") ?? ""), 60)
    const files = form.getAll("file").filter((f) => typeof f === "object" && f.size > 0).slice(0, MAX_FILES)
    if (!body) return json({ error: "empty report" }, 400)

    try {
      const sections = []
      for (const f of files) sections.push(await section(f))
      const description = [body, "", "---", version ? `CatWM ${version}` : "", "", ...sections].join("\n")
      const input = { teamId: env.LINEAR_TEAM_ID, title, description }
      if (env.LINEAR_LABEL_ID) input.labelIds = [env.LINEAR_LABEL_ID]
      const r = await linear(env, `mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier } } }`, { input })
      if (!r.issueCreate?.success) throw new Error("issueCreate failed")
      return json({ id: r.issueCreate.issue.identifier })
    } catch (e) {
      console.error(e)
      return json({ error: "couldn't file the report" }, 502)
    }
  },
}

const MAX_COMMENTS = 10
const num = (v, max) => (typeof v === "number" && Number.isFinite(v) ? Math.min(Math.max(v, 0), max) : 0)
const word = (v, n) => clip(String(v ?? "").replace(/[^\w.:\-]/g, ""), n)

async function perf(req, env) {
  const length = req.headers.get("content-length")
  if (length === null) return json({ error: "length required" }, 411)
  if (Number(length) > 8192) return json({ error: "too large" }, 413)
  let p
  try {
    p = await req.json()
  } catch {
    return json({ error: "bad json" }, 400)
  }
  const fp = word(p.fingerprint, 8)
  const kind = word(p.kind, 60)
  if (!/^[0-9a-f]{8}$/.test(fp) || !kind) return json({ error: "bad report" }, 400)
  const app = p.app && typeof p.app === "object" ? word(p.app.bundle, 120) : ""
  const tags = Array.isArray(p.tags) ? p.tags.slice(0, 6).map((t) => word(t, 20)).join(", ") : ""
  const line = [
    `CatWM ${word(p.version, 20)}`, `macOS ${word(p.os, 10)}`, word(p.hardware, 30), `${num(p.hz, 500)} Hz`,
    `${num(p.displays, 20)} display(s)`, `curve ${word(p.curve, 60)} ${num(p.durationMs, 5000)}ms`,
    p.hangMs > 0 ? `hang ${num(p.hangMs, 600000)}ms` : `p95 ${num(p.p95Ms, 100000)}ms, ${Math.round(num(p.slowShare, 1) * 100)}% slow frames over ${num(p.frames, 100000)}`,
    app ? `app ${app}: ${num(p.app.stepMs, 100000)}ms per AX step, ${Math.round(num(p.app.skipped, 1) * 100)}% skipped` : "",
    tags ? `tags ${tags}` : "",
    `events ${num(p.count, 1000)}`,
  ].filter(Boolean).join(" · ")
  const title = `[perf:${fp}] ${kind}${app ? ` with ${app}` : ""} on macOS ${word(p.os, 10)}`

  try {
    const found = await linear(
      env,
      `query($team: ID!, $t: String!) { issues(first: 1, filter: { team: { id: { eq: $team } }, title: { contains: $t },
         state: { type: { nin: ["completed", "canceled"] } } }) { nodes { id identifier comments(first: ${MAX_COMMENTS + 1}) { nodes { id } } } } }`,
      { team: env.LINEAR_TEAM_ID, t: `[perf:${fp}]` },
    )
    const issue = found.issues.nodes[0]
    if (issue) {
      if (issue.comments.nodes.length <= MAX_COMMENTS) {
        await linear(env, `mutation($i: CommentCreateInput!) { commentCreate(input: $i) { success } }`, { i: { issueId: issue.id, body: `+1 · ${line}` } })
      }
      return json({ id: issue.identifier, duplicate: true })
    }
    const input = { teamId: env.LINEAR_TEAM_ID, title, description: `Filed automatically by CatWM.\n\n${line}` }
    const labels = [env.LINEAR_LABEL_ID, env.LINEAR_PERF_LABEL_ID].filter(Boolean)
    if (labels.length) input.labelIds = labels
    const r = await linear(env, `mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier } } }`, { input })
    if (!r.issueCreate?.success) throw new Error("issueCreate failed")
    return json({ id: r.issueCreate.issue.identifier })
  } catch (e) {
    console.error(e)
    return json({ error: "couldn't file the report" }, 502)
  }
}

async function section(file) {
  let text = await file.text()
  if (text.length > MAX_FILE_CHARS) text = "…\n" + text.slice(-MAX_FILE_CHARS)
  const name = clip(file.name.replace(/[^\w.\- ]/g, ""), 60)
  return `+++ ${name}\n~~~~\n${text.replaceAll("~~~~", "~~~")}\n~~~~\n+++\n`
}

async function linear(env, query, variables) {
  const res = await fetch("https://api.linear.app/graphql", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: env.LINEAR_API_KEY },
    body: JSON.stringify({ query, variables }),
  })
  const data = await res.json()
  if (data.errors) throw new Error(JSON.stringify(data.errors))
  return data.data
}

const clip = (s, n) => (s.length > n ? s.slice(0, n) : s)
const json = (obj, status = 200) => Response.json(obj, { status })
