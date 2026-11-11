import XCTest

/// UI tests for the local single-device demo. Every launch passes -STEADY_UITEST so the
/// app wipes its saved state first and starts from the fictional seed data.
final class SteadyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-STEADY_UITEST", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    // MARK: Helpers

    private func launch(extraArguments: [String] = []) {
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["primaryAddButton"].waitForExistence(timeout: 20), "Today screen did not appear")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Any element whose accessibility label contains the text (rows combine their children).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func switchRole(_ title: String) {
        let button = app.segmentedControls["rolePicker"].buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Role button \(title) missing")
        button.tap()
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 10))
    }

    private func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab \(title) missing")
        tab.tap()
    }

    /// The menu-style picker's button label also carries the current value ("Entry type, Observations"),
    /// so find it by identifier or label prefix, then pick the item from the opened menu.
    private func chooseEntryType(_ title: String) {
        let byID = app.buttons["entryTypePicker"]
        let byLabel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Entry type")).firstMatch
        let picker = byID.waitForExistence(timeout: 10) ? byID : byLabel
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Entry type picker missing")
        picker.tap()
        let item = app.buttons[title].exists ? app.buttons[title] : app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Menu item \(title) missing")
        item.tap()
    }

    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        _ = element.waitForExistence(timeout: 10)
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)")
    }

    /// Waits for the app's notice alert, checks its title, captures it, taps OK and waits for it to go away.
    private func dismissAlert(expectingTitle title: String, screenshot name: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Expected alert \"\(title)\" did not appear")
        XCTAssertTrue(alert.label.contains(title) || alert.staticTexts[title].exists, "Unexpected alert: \(alert.debugDescription)")
        shot(name)
        let ok = alert.buttons["OK"]
        XCTAssertTrue(ok.exists, "Alert has no OK button")
        ok.tap()
        XCTAssertTrue(waitForDisappearance(alert), "Alert \"\(title)\" did not dismiss")
    }

    private func addEntry(title: String, body: String, intensityTaps: Int = 0) {
        let add = app.buttons["primaryAddButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let titleField = app.textFields["entryTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        let bodyField = app.textFields["entryBody"].exists ? app.textFields["entryBody"] : app.textViews["entryBody"]
        if bodyField.waitForExistence(timeout: 5) { bodyField.tap(); bodyField.typeText(body) }
        if intensityTaps > 0 {
            let stepper = app.steppers["intensityStepper"]
            XCTAssertTrue(stepper.waitForExistence(timeout: 5))
            for _ in 0..<intensityTaps { stepper.buttons.element(boundBy: 1).tap() }
        }
        shot("editor-\(title)")
        let save = app.buttons["saveEntry"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["primaryAddButton"].waitForExistence(timeout: 10), "Editor did not close")
    }

    private func setGrant(role: String, action: String, kind: String) {
        let disclosure = app.staticTexts["disclosure-\(role)-\(kind)"]
        scrollUntilHittable(disclosure)
        disclosure.tap()
        let toggle = app.switches["grant-\(role)-\(action)-\(kind)"]
        scrollUntilHittable(toggle)
        // Tap the trailing edge so the switch itself, not the label, receives the tap.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    // MARK: Flows

    func testSurvivorLogsSymptomAndJournalShowsIt() {
        launch()
        shot("01-today-survivor")
        addEntry(title: "Bright lights tiring", body: "Fictional UI test entry", intensityTaps: 1)
        openTab("Journal")
        let row = element(containing: "Bright lights tiring")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Logged symptom missing from Journal")
        XCTAssertTrue(element(containing: "Intensity 3 of 5").exists, "Intensity not shown in Journal")
        shot("02-journal-with-new-symptom")
    }

    func testFilesTabPreviewOfFictionalMRI() {
        launch()
        openTab("Files")
        XCTAssertTrue(app.staticTexts["Fictional attachments only"].waitForExistence(timeout: 10))
        let preview = app.buttons["previewFile"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Sample MRI row missing")
        shot("03-files-list")
        preview.tap()
        XCTAssertTrue(app.navigationBars["Fictional file preview"].waitForExistence(timeout: 15), "Preview sheet did not appear")
        let image = app.images["filePreviewImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10), "Preview image did not render")
        XCTAssertFalse(image.frame.isEmpty, "Preview image has an empty frame")
        XCTAssertGreaterThan(image.frame.width, 0)
        XCTAssertGreaterThan(image.frame.height, 0)
        shot("04-quicklook-fictional-mri")
        app.navigationBars["Fictional file preview"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Fictional file preview"].waitForNonExistence(timeout: 10), "Preview sheet did not close")
        XCTAssertTrue(app.staticTexts["Fictional attachments only"].waitForExistence(timeout: 10))
    }

    func testControlTabTogglesCaregiverPermission() {
        launch()
        openTab("Control")
        XCTAssertTrue(app.staticTexts["The survivor stays in control"].waitForExistence(timeout: 10))
        setGrant(role: "caregiver", action: "read", kind: "symptoms")
        let toggle = app.switches["grant-caregiver-read-symptoms"]
        XCTAssertEqual(toggle.value as? String, "1", "Caregiver read Symptoms should now be on")
        shot("05-control-caregiver-read-granted")
        // The caregiver can now read symptom history in the Journal.
        switchRole("Caregiver")
        openTab("Journal")
        chooseEntryType("Symptoms")
        XCTAssertTrue(element(containing: "Noise felt tiring").waitForExistence(timeout: 10), "Granted history should be readable")
        XCTAssertFalse(element(containing: "History is private").exists)
        shot("06-caregiver-reads-granted-history")
    }

    func testCaregiverObservationPrivateHistoryAndCheckIn() {
        launch()
        switchRole("Caregiver")
        shot("07-today-caregiver")
        addEntry(title: "Rested after noise", body: "Fictional caregiver observation")
        openTab("Journal")
        XCTAssertTrue(element(containing: "Rested after noise").waitForExistence(timeout: 10), "Observation missing")
        // Symptom history is private to the caregiver by default.
        chooseEntryType("Symptoms")
        XCTAssertTrue(element(containing: "History is private").waitForExistence(timeout: 10), "Private state not shown")
        XCTAssertFalse(element(containing: "Noise felt tiring").exists, "Symptom history leaked to caregiver")
        shot("08-caregiver-history-private")
        // Suggest a check-in and a break; the survivor sees the card and can dismiss it.
        openTab("Today")
        let suggest = app.buttons["Suggest a check-in"]
        scrollUntilHittable(suggest)
        suggest.tap()
        // The app confirms with a modal alert that covers the Today screen until dismissed.
        dismissAlert(expectingTitle: "Check-in saved", screenshot: "09a-caregiver-checkin-saved")
        let breakButton = app.buttons["Suggest taking a break"]
        scrollUntilHittable(breakButton)
        breakButton.tap()
        dismissAlert(expectingTitle: "Prompt saved", screenshot: "09-caregiver-suggested")
        switchRole("Survivor")
        let card = element(containing: "A gentle check-in")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Survivor should see the check-in card")
        shot("10-survivor-checkin-card")
        let dismiss = app.buttons["Dismiss check-in"]
        scrollUntilHittable(dismiss)
        dismiss.tap()
        XCTAssertTrue(waitForDisappearance(card), "Check-in card should be dismissed")
    }

    func testClinicianNoteAndAttachmentUploadOnlyWhenGranted() {
        launch()
        switchRole("Clinician")
        addEntry(title: "Review noise triggers", body: "Fictional clinician note")
        openTab("Journal")
        XCTAssertTrue(element(containing: "Review noise triggers").waitForExistence(timeout: 10), "Note missing")
        openTab("Files")
        XCTAssertTrue(app.buttons["previewFile"].waitForExistence(timeout: 10), "Clinician may read shared files by default")
        XCTAssertFalse(app.buttons["importFile"].exists, "Upload must be hidden until granted")
        shot("11-clinician-files-no-upload")
        // Survivor grants add on Files for the clinician.
        switchRole("Survivor")
        openTab("Control")
        setGrant(role: "clinician", action: "add", kind: "attachments")
        shot("12-control-clinician-upload-granted")
        switchRole("Clinician")
        openTab("Files")
        XCTAssertTrue(app.buttons["importFile"].waitForExistence(timeout: 10), "Upload should appear once granted")
        shot("13-clinician-files-upload-available")
    }

    func testResetDemoRestoresSeeds() {
        launch()
        addEntry(title: "Temporary entry", body: "Fictional, to be reset")
        openTab("Journal")
        XCTAssertTrue(element(containing: "Temporary entry").waitForExistence(timeout: 10))
        openTab("Control")
        let reset = app.buttons["resetDemo"]
        scrollUntilHittable(reset)
        reset.tap()
        let confirm = app.buttons["Reset demo"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        openTab("Journal")
        XCTAssertTrue(element(containing: "Noise felt tiring").waitForExistence(timeout: 10), "Seed entry not restored")
        XCTAssertFalse(element(containing: "Temporary entry").exists, "Added entry survived reset")
        shot("14-after-reset")
    }

    func testTodayAtAccessibilityExtraLargeDynamicType() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.buttons["primaryAddButton"].isHittable || app.buttons["primaryAddButton"].exists)
        XCTAssertTrue(app.staticTexts["Today"].exists || app.navigationBars["Today"].exists)
        shot("15-today-accessibility-xl")
    }

    // MARK: Accessibility audit

    private var auditIssues: [String] = []

    /// Runs the system accessibility audit on the current screen. Every issue is printed with the
    /// stable marker A11Y_ISSUE (screen, type, compact description, element) so it appears in CI logs.
    /// Issues are collected, not failed one by one, so a single run reports everything on every screen.
    /// No audit type or element is excluded: the handler only logs and returns false (issue is kept).
    @available(iOS 17.0, *)
    private func auditCurrentScreen(_ name: String) throws {
        var count = 0
        print("A11Y_AUDIT_SCREEN begin \(name)")
        try app.performAccessibilityAudit { issue in
            count += 1
            let element = issue.element.map { String(describing: $0).replacingOccurrences(of: "\n", with: " ") } ?? "none"
            let line = "A11Y_ISSUE screen=\(name) type=\(issue.auditType.rawValue) compact=\(issue.compactDescription) detail=\(issue.detailedDescription) element=\(element)"
            print(line)
            self.auditIssues.append(line)
            return false
        }
        print("A11Y_AUDIT_SCREEN end \(name) issues=\(count)")
    }

    /// Separate from the functional flows so a failing audit is distinguishable and CI reports it on its own.
    func testAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit needs iOS 17 or later") }
        launch()
        try auditCurrentScreen("today-survivor")

        // Editor sheet (survivor, symptoms).
        app.buttons["primaryAddButton"].tap()
        XCTAssertTrue(app.textFields["entryTitle"].waitForExistence(timeout: 10), "Editor did not open")
        try auditCurrentScreen("editor-sheet")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["primaryAddButton"].waitForExistence(timeout: 10), "Editor did not close")

        openTab("Journal")
        XCTAssertTrue(element(containing: "Noise felt tiring").waitForExistence(timeout: 10), "Journal seed entry missing")
        try auditCurrentScreen("journal")

        openTab("Files")
        let preview = app.buttons["previewFile"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Sample MRI row missing")
        try auditCurrentScreen("files")
        preview.tap()
        XCTAssertTrue(app.navigationBars["Fictional file preview"].waitForExistence(timeout: 15), "Preview sheet did not appear")
        XCTAssertTrue(app.images["filePreviewImage"].waitForExistence(timeout: 10), "Preview image did not render")
        try auditCurrentScreen("file-preview")
        app.navigationBars["Fictional file preview"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Fictional file preview"].waitForNonExistence(timeout: 10), "Preview sheet did not close")

        openTab("Control")
        XCTAssertTrue(app.staticTexts["The survivor stays in control"].waitForExistence(timeout: 10))
        try auditCurrentScreen("control")

        openTab("Today")
        switchRole("Caregiver")
        XCTAssertTrue(app.buttons["Suggest a check-in"].waitForExistence(timeout: 10), "Caregiver Today did not appear")
        try auditCurrentScreen("today-caregiver")

        print("A11Y_AUDIT_TOTAL issues=\(auditIssues.count)")
        XCTAssertTrue(auditIssues.isEmpty, "Accessibility audit found \(auditIssues.count) issue(s); see A11Y_ISSUE lines in the log")
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
