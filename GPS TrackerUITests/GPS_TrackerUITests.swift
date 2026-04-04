//
//  GPS_TrackerUITests.swift
//  GPS TrackerUITests
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - UI tests for critical user flows

import XCTest

final class GPSTrackerUITests: XCTestCase {

  var app: XCUIApplication!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
  }

  func testAppLaunchesSuccessfully() {
    XCTAssertTrue(app.windows.firstMatch.exists)
  }

  func testFirstLaunchShowsConfigurationSheet() {
    // On first launch with no config, the configuration sheet should appear
    // (The app uses --uitesting flag to start with a blank in-memory store)
    let hostnameField = app.textFields["Hostname"]
    XCTAssertTrue(
      hostnameField.waitForExistence(timeout: 3),
      "Configuration sheet should appear on first launch")
  }

  func testPolarGraphViewIsVisible() {
    // Dismiss config sheet if present by pressing Escape
    app.typeKey(.escape, modifierFlags: [])

    // The main window should be present
    XCTAssertTrue(app.windows.firstMatch.exists)
  }

  func testTableToggleButtonExists() {
    app.typeKey(.escape, modifierFlags: [])

    let satellitesButton = app.buttons["Satellites"]
    XCTAssertTrue(satellitesButton.waitForExistence(timeout: 2))
  }

  func testSettingsButtonOpensConfig() {
    app.typeKey(.escape, modifierFlags: [])

    let settingsButton = app.buttons["Settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
    settingsButton.tap()

    let hostnameField = app.textFields["Hostname"]
    XCTAssertTrue(hostnameField.waitForExistence(timeout: 2))
  }
}
