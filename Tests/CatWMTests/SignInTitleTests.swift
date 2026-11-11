@testable import CatWMKit
import Testing

@MainActor @Suite struct SignInTitleTests {
    @Test(arguments: ["Sign in", "sign in", "SIGN IN", "Signin", "Sign-in", "Log in", "login", "Log-In",
                      "Sign in to Slack", "Sign in: Google", "Sign in|Acme", "Log in, please",
                      "Sign in – Acme", "Sign in — Acme", "sign in\tnow", "Login page"])
    func aSignInTitleFloats(_ title: String) {
        #expect(WindowManager.isSignInTitle(title))
    }

    @Test(arguments: ["", "Sign", "Signing in", "Sign up", "Sign  in", "Logins", "Log", "Please sign in",
                      "Design", "Blog in progress", "sign ins"])
    func anotherTitleDoesNot(_ title: String) {
        #expect(!WindowManager.isSignInTitle(title))
    }
}
