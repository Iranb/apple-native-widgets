// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

@main
struct HPCAvailabilityTests {
    static func main() {
        check(reported: 32, allocated: 0, total: 32, expected: 32)
        check(reported: nil, allocated: 0, total: 32, expected: 32)
        check(reported: 0, allocated: 0, total: 32, expected: 32)
        check(reported: 0, allocated: 32, total: 32, expected: 0)
        check(reported: 99, allocated: 4, total: 8, expected: 4)
        check(reported: 3, allocated: nil, total: 8, expected: 3)
        check(reported: nil, allocated: nil, total: 8, expected: 0)
        check(reported: -1, allocated: nil, total: nil, expected: 0)
        print("Availability resolver tests passed")
    }

    private static func check(reported: Int?, allocated: Int?, total: Int?, expected: Int) {
        let actual = resolvedAvailableCount(reported: reported, allocated: allocated, total: total)
        precondition(
            actual == expected,
            "Expected \(expected), got \(actual) for reported=\(String(describing: reported)), allocated=\(String(describing: allocated)), total=\(String(describing: total))"
        )
    }
}
