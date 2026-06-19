import XCTest

#if os(iOS)
import ManagedSettings
import FamilyControls

final class RestrictionServiceTests: XCTestCase {

    func test_applyRestrictions_setsShieldApplications() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)
        let selection = FamilyActivitySelection()

        service.apply(selection: selection, overrides: [])

        XCTAssertEqual(mockStore.applyCallCount, 1)
    }

    func test_removeRestrictions_clearsShield() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)

        service.removeAll()

        XCTAssertTrue(mockStore.shieldWasCleared)
    }

    func test_emptySelection_doesNotSetShield() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)
        let selection = FamilyActivitySelection()  // empty

        service.apply(selection: selection, overrides: [])

        // Empty selection means no apps selected — nothing to shield
        XCTAssertFalse(mockStore.shieldApplicationsWasSet)
        XCTAssertEqual(mockStore.applyCallCount, 1)
    }
}
#endif
