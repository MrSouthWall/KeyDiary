import ServiceManagement
import XCTest
@testable import KeyDiary

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testRegistrationCanStartWhenServiceHasNoExistingRecord() {
        XCTAssertTrue(
            LaunchAtLoginController.canAttemptRegistration(from: .notFound)
        )
    }

    func testRegistrationCanStartWhenServiceIsNotRegistered() {
        XCTAssertTrue(
            LaunchAtLoginController.canAttemptRegistration(from: .notRegistered)
        )
    }

    func testRegistrationDoesNotRepeatForRegisteredService() {
        XCTAssertFalse(
            LaunchAtLoginController.canAttemptRegistration(from: .enabled)
        )
        XCTAssertFalse(
            LaunchAtLoginController.canAttemptRegistration(from: .requiresApproval)
        )
    }
}
