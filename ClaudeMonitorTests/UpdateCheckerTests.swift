// ClaudeMonitorTests/UpdateCheckerTests.swift
import XCTest
@testable import ClaudeMonitor

final class UpdateCheckerTests: XCTestCase {

    func test_newer_patch_and_minor_and_major() {
        XCTAssertTrue(SemVer.isNewer("1.4.1", than: "1.4.0"))
        XCTAssertTrue(SemVer.isNewer("1.5.0", than: "1.4.0"))
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.9.9"))
    }

    func test_same_or_older_is_not_newer() {
        XCTAssertFalse(SemVer.isNewer("1.4.0", than: "1.4.0"))
        XCTAssertFalse(SemVer.isNewer("1.4.0", than: "1.5.0"))
        XCTAssertFalse(SemVer.isNewer("1.3.9", than: "1.4.0"))
    }

    func test_numeric_not_lexical() {
        // 문자열 비교라면 "1.10.0" < "1.9.0" 이 되어버림 — 숫자 비교여야 한다
        XCTAssertTrue(SemVer.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(SemVer.isNewer("1.9.0", than: "1.10.0"))
    }

    func test_differing_component_counts() {
        XCTAssertTrue(SemVer.isNewer("1.4.1", than: "1.4"))
        XCTAssertFalse(SemVer.isNewer("1.4", than: "1.4.0"))
    }

    func test_malformed_is_safe() {
        XCTAssertFalse(SemVer.isNewer("", than: "1.4.0"))
        XCTAssertFalse(SemVer.isNewer("abc", than: "1.4.0"))
    }

    func test_parses_version_from_info_plist() {
        let plist = """
        <plist><dict>
        <key>CFBundleShortVersionString</key>
        <string>1.4.0</string>
        <key>CFBundleVersion</key>
        <string>8</string>
        </dict></plist>
        """
        XCTAssertEqual(UpdateChecker.parseVersion(fromInfoPlist: plist), "1.4.0")
    }
}
