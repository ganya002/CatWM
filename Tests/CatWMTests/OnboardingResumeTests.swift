@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct OnboardingResumeTests {
    @Test func unfinishedOnboardingResumesAfterAccessibilityGrant() {
        #expect(Onboarding.shouldShow(firstRun: false, trusted: true, done: false, started: true))
    }

    @Test func finishedOnboardingStaysHidden() {
        #expect(!Onboarding.shouldShow(firstRun: false, trusted: true, done: true, started: true))
        #expect(!Onboarding.shouldShow(firstRun: false, trusted: false, done: true, started: true))
    }

    @Test func userWhoNeverStartedOnboardingDoesNotSeeIt() {
        #expect(!Onboarding.shouldShow(firstRun: false, trusted: true, done: false, started: false))
    }

    @Test func firstRunAndMissingAccessibilityStillShowIt() {
        #expect(Onboarding.shouldShow(firstRun: true, trusted: true, done: false, started: false))
        #expect(Onboarding.shouldShow(firstRun: false, trusted: false, done: false, started: false))
    }
}
