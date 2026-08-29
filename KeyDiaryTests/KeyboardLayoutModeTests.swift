//
//  KeyboardLayoutModeTests.swift
//  KeyDiaryTests
//

import XCTest
@testable import KeyDiary

final class KeyboardLayoutModeTests: XCTestCase {
    func testAlphabeticalLayoutContainsEveryLetterInOrder() {
        let letters = KeyboardLayoutMode.alphabetical.letterRows.flatMap { $0 }

        XCTAssertEqual(String(letters), "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        XCTAssertEqual(
            KeyboardLayoutMode.alphabetical.letterRows.map(\.count),
            [10, 9, 7]
        )
    }

    func testEveryLayoutContainsEachLetterExactlyOnce() {
        let expectedLetters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

        for layout in KeyboardLayoutMode.allCases {
            let letters = layout.letterRows.flatMap { $0 }
            XCTAssertEqual(letters.count, 26)
            XCTAssertEqual(Set(letters), expectedLetters)
        }
    }
}
