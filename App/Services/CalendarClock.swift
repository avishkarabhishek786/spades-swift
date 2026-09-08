import Foundation

/// The calendar boundary.
///
/// `SpadesEconomy` takes day-keys and a monotonic reading as inputs and never
/// touches `Calendar`, `TimeZone` or `Date()`. This type is where those become
/// values. Keeping the conversion here is what makes the clock-rollback rule
/// testable without a device, and what stops the economy suite passing in one
/// CI region and failing in another.
struct CalendarClock: Sendable {
    private let calendar: Calendar
    private let wallClock: @Sendable () -> Date
    private let monotonic: @Sendable () -> UInt64

    init(
        calendar: Calendar = .current,
        wallClock: @escaping @Sendable () -> Date = { Date() },
        monotonic: @escaping @Sendable () -> UInt64 = CalendarClock.systemMonotonicSeconds
    ) {
        self.calendar = calendar
        self.wallClock = wallClock
        self.monotonic = monotonic
    }

    var now: Date { wallClock() }

    /// Seconds from a clock that keeps running while the device sleeps and
    /// resets on reboot. Never wall time — the whole point is that a player
    /// changing the date does not move it.
    var monotonicSeconds: UInt64 { monotonic() }

    /// Today in the user's calendar, "yyyy-MM-dd".
    var dayKey: String { Self.dayKey(for: now, calendar: calendar) }

    /// Yesterday in the user's calendar.
    ///
    /// The economy module needs this because deciding whether two day-keys are
    /// consecutive is calendar arithmetic — month lengths, leap years — and
    /// that is exactly what may not happen in there.
    var previousDayKey: String {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return Self.dayKey(for: yesterday, calendar: calendar)
    }

    /// Built from `DateComponents` rather than a `DateFormatter` so it cannot
    /// pick up a locale's alternate calendar and silently change shape.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `CLOCK_MONOTONIC` on Darwin keeps counting while the device is asleep,
    /// which is what the anti-cheat needs: a phone left overnight advances it by
    /// a day whether or not the app was running.
    static let systemMonotonicSeconds: @Sendable () -> UInt64 = {
        UInt64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000_000)
    }
}
