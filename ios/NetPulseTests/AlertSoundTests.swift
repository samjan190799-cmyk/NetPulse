//
//  AlertSoundTests.swift
//  NetPulseTests
//
//  Created for iOS (Swift 6.0+ / SwiftUI) - 2026.
//

import AudioToolbox
import XCTest
@testable import NetPulse

/// Звук предупреждения тихий и редкий: один щелчок не чаще раза в пять минут.
@MainActor
final class AlertSoundTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstSoundPlaysAndRepeatsWithinIntervalAreSilent() {
        var gate = AlertSoundThrottle(minimumInterval: 300)

        XCTAssertTrue(gate.claim(at: start))
        XCTAssertFalse(gate.claim(at: start.addingTimeInterval(60)))
        XCTAssertFalse(gate.claim(at: start.addingTimeInterval(299)))
        XCTAssertTrue(gate.claim(at: start.addingTimeInterval(300)))
    }

    func testSilentAttemptsDoNotExtendTheSilence() {
        // Тишина отсчитывается от последнего сыгранного звука, а не от последнего предупреждения
        var gate = AlertSoundThrottle(minimumInterval: 300)

        XCTAssertTrue(gate.claim(at: start))
        for minute in 1...4 {
            XCTAssertFalse(gate.claim(at: start.addingTimeInterval(Double(minute) * 60)))
        }
        XCTAssertTrue(gate.claim(at: start.addingTimeInterval(301)))
    }

    func testClockMovedBackDoesNotMuteSoundForHours() {
        var gate = AlertSoundThrottle(minimumInterval: 300)

        XCTAssertTrue(gate.claim(at: start))
        XCTAssertTrue(gate.claim(at: start.addingTimeInterval(-3600)))
    }

    func testLongOutageProducesOneSoundEveryFiveMinutes() {
        // Предупреждение о затянувшемся сбое повторяется каждую минуту, как и раньше, а звук играет раз в пять минут
        var played: [SystemSoundID] = []
        var now = start
        let sound = AlertSound(player: { played.append($0) }, clock: { now })

        for minute in 0...20 {
            now = start.addingTimeInterval(Double(minute) * 60)
            sound.playIfDue()
        }

        XCTAssertEqual(played.count, 5, "звук на 0, 5, 10, 15 и 20 минутах")
    }

    func testPlaysShortClickInsteadOfTheOldTriTone() {
        var played: [SystemSoundID] = []
        let sound = AlertSound(player: { played.append($0) }, clock: { self.start })

        XCTAssertTrue(sound.playIfDue())

        XCTAssertEqual(played, [AlertSound.soundID])
        XCTAssertNotEqual(AlertSound.soundID, 1007, "1007 — прежняя «тройная» мелодия SMS")
        XCTAssertEqual(AlertSound.minimumInterval, 300)
    }
}
