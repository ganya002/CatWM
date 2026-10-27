import { HandleSSOCallback } from "@clerk/react-router";
import { redirect, useNavigate } from "react-router";

import { clerkReady } from "~/roadmap/access.server";

export function loader() {
  if (!clerkReady()) throw redirect("/roadmap/dev");
  return null;
}

export default function SSOCallback() {
  const navigate = useNavigate();
  const home = () => void navigate("/roadmap/dev", { replace: true });
  return (
    <main className="gate">
      <p className="gate__line">Signing in…</p>
      <HandleSSOCallback navigateToApp={home} navigateToSignIn={home} navigateToSignUp={home} />
    </main>
  );
}
