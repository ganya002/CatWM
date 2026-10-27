import { type RouteConfig, index, layout, route } from "@react-router/dev/routes";

export default [
  index("routes/home.tsx"),
  route("features", "routes/features.tsx"),
  route("roadmap", "routes/roadmap.tsx"),
  route("api/roadmap", "routes/api.roadmap.ts"),
  route("api/github", "routes/api.github.ts"),
  layout("routes/developer.tsx", [
    route("roadmap/dev", "routes/roadmap.dev.tsx"),
    route("roadmap/sso-callback", "routes/roadmap.sso-callback.tsx"),
  ]),
] satisfies RouteConfig;
