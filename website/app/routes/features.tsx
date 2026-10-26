import { Features } from "~/features/Features";

const DESCRIPTION = "Every CatWM feature, with the keys, the command and the setting for each.";

export function meta() {
  return [
    { title: "CatWM features" },
    { name: "description", content: DESCRIPTION },
    { name: "theme-color", content: "#000000" },
  ];
}

export default function FeaturesPage() {
  return <Features />;
}
