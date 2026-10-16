import { kv } from "void/kv";

type Signup = { email: string; createdAt: string };

const signups = kv.map<Signup>("signups");

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function addSignup(raw: FormDataEntryValue | null) {
  const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (!EMAIL.test(email) || email.length > 254) {
    return { ok: false as const, error: "Enter a valid email." };
  }
  if (!(await signups.get(email))) {
    await signups.put(email, { email, createdAt: new Date().toISOString() });
  }
  return { ok: true as const };
}
