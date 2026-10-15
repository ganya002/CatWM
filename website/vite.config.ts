import { reactRouter } from "@react-router/dev/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig, lazyPlugins } from "vite-plus";
import { voidPlugin } from "void";

export default defineConfig({
  fmt: {},
  lint: {
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
  // Void must come before the React Router plugin.
  plugins: lazyPlugins(() => [voidPlugin(), tailwindcss(), reactRouter()]),
  resolve: {
    tsconfigPaths: true,
  },
});
