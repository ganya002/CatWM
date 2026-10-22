import { defineConfig } from "void/config";

export default defineConfig({
  cloudflare: {
    account_id: "865dded96630ca6a533584a80efad356",
    compatibility_date: "2026-02-24",
    routes: [
      { pattern: "catwm.perwko.com", custom_domain: true },
      { pattern: "ouch.perwko.com", custom_domain: true },
    ],
    workers_dev: false,
    preview_urls: true,
  },
});
