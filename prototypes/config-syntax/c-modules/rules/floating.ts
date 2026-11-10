// PROTOTYPE for #342, candidate C. The floating apps module.
import { floating } from "catwm"

export default floating({
  apps: ["com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.calculator"],
  listed: "float",
  smallWindows: true,
})
