// Receives bug reports from Ouch and files them as Linear issues. The Linear API key stays here:
// anything shipped inside the app can be pulled out of it. The key only needs "Create issues", so
// the files go into the issue itself as collapsible sections instead of uploads.
//
// POST /report, multipart form: title, body, version, and up to 6 `file` parts.
// Secrets/vars: LINEAR_API_KEY (secret), LINEAR_TEAM_ID (the team's UUID), optional LINEAR_LABEL_ID.

const MAX_BYTES = 4 * 1024 * 1024
const MAX_FILES = 6
// Per file, from the end: the newest log lines matter most.
const MAX_FILE_CHARS = 40000

export default {
  async fetch(req, env) {
    const url = new URL(req.url)
    if (req.method !== "POST" || url.pathname !== "/report") return json({ error: "not found" }, 404)

    // Ouch sends a handful of reports at most; anything faster is someone poking at the endpoint.
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: req.headers.get("cf-connecting-ip") ?? "unknown" })
      if (!success) return json({ error: "too many reports" }, 429)
    }
    if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) return json({ error: "too large" }, 413)

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
      const description = [body, "", "---", version ? `Ouch ${version}` : "", "", ...sections].join("\n")
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

// A file as a collapsed block in the issue: Linear's `+++ title` … `+++` syntax.
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
