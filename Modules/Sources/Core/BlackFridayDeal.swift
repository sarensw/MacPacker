//
//  BlackFridayDeal.swift
//  Modules
//
//  Black Friday 2026: the other apps by the same developer are 30% off. The
//  welcome window and the More Apps menu show the deal until its last day is
//  over, then go back to how they were. Remove this and its uses after that.
//

import Foundation

public enum BlackFridayDeal {
    /// Whether the deal still runs at `date`: through Dec 2, 2026, in the
    /// user's time zone.
    public static func isActive(at date: Date = .now, timeZone: TimeZone = .current) -> Bool {
        date < start(of: DateComponents(year: 2026, month: 12, day: 3), in: timeZone)
    }

    /// The deal's last day as the user's region writes it, like "Dec 2".
    public static func lastDayText(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
        return start(of: DateComponents(year: 2026, month: 12, day: 2), in: timeZone).formatted(style)
    }

    /// Midnight starting that day, read in the Gregorian calendar whatever
    /// calendar the user picked: in the Buddhist one, year 2026 is 1483.
    private static func start(of day: DateComponents, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: day)!
    }
}
