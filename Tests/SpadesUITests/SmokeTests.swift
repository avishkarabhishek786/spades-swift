import XCTest

/// The one UI test required by §13: launch, start a solo Casual game, play a
/// full hand through accessibility identifiers, and assert the score screen.
///
/// It drives the app the way a player does. Card views are only hittable when
/// `LegalMoves` says they are playable, so "tap any hittable card" is also a
/// live check that the table never offers an illegal move.
final class SmokeTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    func testPlaysAFullHandAndReachesTheScoreScreen() throws {
        // Lobby
        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()

        let casual = app.buttons["stake.casual"]
        XCTAssertTrue(casual.waitForExistence(timeout: 5))
        casual.tap()

        app.buttons["startMatchButton"].tap()

        // Skip the deal animation rather than waiting it out.
        let scoreBar = app.otherElements["scoreBar"]
        XCTAssertTrue(scoreBar.waitForExistence(timeout: 10))
        app.tap()

        // Bidding: the bots bid first, so wait for our turn.
        let bidBar = app.otherElements["biddingBar"]
        XCTAssertTrue(bidBar.waitForExistence(timeout: 20), "The bid bar never appeared")
        let bid = app.buttons["bid.3"]
        XCTAssertTrue(bid.waitForExistence(timeout: 5))
        bid.tap()

        // Play the hand. Thirteen tricks, one card of ours per trick, plus
        // slack for bot turns and the trick pause.
        let summary = app.otherElements["handSummary"]
        let deadline = Date().addingTimeInterval(180)

        while !summary.exists, Date() < deadline {
            if let card = firstPlayableCard() {
                card.tap()
            }
            _ = summary.waitForExistence(timeout: 2)
        }

        XCTAssertTrue(summary.exists, "The hand never reached the score screen")
        XCTAssertTrue(app.buttons["continueButton"].exists)
    }

    /// Any card the table is currently willing to accept.
    private func firstPlayableCard() -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.'")
        let cards = app.descendants(matching: .any).matching(predicate)
        for index in 0..<cards.count {
            let card = cards.element(boundBy: index)
            if card.exists, card.isHittable { return card }
        }
        return nil
    }

    func testSettingsExposeTheAccessibilityAndAbuseControls() throws {
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()

        // The mute controls ship before the reactions do (§8).
        let hideReactions = app.switches["hideReactionsToggle"]
        XCTAssertTrue(hideReactions.waitForExistence(timeout: 5))

        // The four-colour deck is an accessibility requirement, not a novelty.
        XCTAssertTrue(app.buttons["deckPalettePicker"].exists || app.otherElements["deckPalettePicker"].exists)
    }
}
