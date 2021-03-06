//
//  File.swift
//  
//
//  Created by Jason Jobe on 7/9/20.
//

import Foundation

public extension Date {
    
    init (julianDate: Double) {
        let JD_JAN_1_1970_0000GMT = 2440587.5
        self = Date(timeIntervalSince1970: (julianDate - JD_JAN_1_1970_0000GMT) * 86400)
    }
    
    var julianDate: Double {
        let JD_JAN_1_1970_0000GMT = 2440587.5
        return JD_JAN_1_1970_0000GMT + timeIntervalSince1970 / 86400
    }
    
    var julianDay: Int {
        let JD_JAN_1_1970_0000GMT = 2440587.5
        return Int (JD_JAN_1_1970_0000GMT + timeIntervalSince1970 / 86400)
    }
    
    var even_day: Bool {
        return julianDay % 2 == 0
    }
    
    var odd_day: Bool {
        return julianDay % 2 != 0
    }

}

// https://www.datetimeformatter.com/how-to-format-date-time-in-swift/
// https://schiavo.me/2019/formatting-dates/

public extension Calendar {
    enum Frequency: CaseIterable {
        case daily, weekly, biweekly,
             monthly, bimonthly, quarterly, yearly
        
        public var name: String { "\(self)" }
        public var step: Int { (self == .biweekly ? 2 : 1) }
        
        public static func named(_ name: String) -> Frequency? {
            Frequency.allCases.first(where: { $0.name == name })
        }
        
        public func nextDate(from date: Date?, in cal: Calendar = Calendar.current) -> Date? {
            guard let date = date else { return nil }
            var dateComponent = DateComponents()
            switch self {
                //                case .once: return date
                case .daily: dateComponent.day = 1
                case .weekly: dateComponent.weekOfYear = 1
                case .biweekly: dateComponent.weekOfYear = 2
                case .monthly: dateComponent.month = 1
                case .bimonthly: dateComponent.month = 2
                case .quarterly: dateComponent.quarter = 1
                case .yearly: dateComponent.year = 1
            }
            return Calendar.current.date(byAdding: dateComponent, to: date)
        }
    }
}

public extension Calendar {
    
    func dateRange(start: Date,
                   end: Date,
                   stepUnits: Calendar.Component,
                   stepValue: Int) -> DateRange {
        let dateRange = DateRange(calendar: self,
                                  start: start,
                                  end: end,
                                  stepUnits: stepUnits,
                                  stepValue: stepValue)
        return dateRange
    }
    
}


public struct DateRange: Sequence, IteratorProtocol {
    
    var calendar: Calendar
    var start: Date
    var end: Date
    var stepUnits: Calendar.Component
    var stepValue: Int
    
    private var multiplier: Int
    
    
    public init(calendar: Calendar, start: Date, end: Date, stepUnits: Calendar.Component, stepValue: Int) {
        self.calendar = calendar
        self.start = start
        self.end = end
        self.stepUnits = stepUnits
        self.stepValue = stepValue
        self.multiplier = 0
    }
    
    // https://developer.apple.com/documentation/foundation/nscalendar/1416165-nextdate
    
    mutating public func next() -> Date? {
        guard let nextDate = calendar.date(byAdding: stepUnits,
                                           value: stepValue * multiplier,
                                           to: start,
                                           wrappingComponents: false) else {
            return nil
        }
        guard nextDate < end else { return nil }
        
        multiplier += 1
        return nextDate
    }
    
}

public struct Recur {
    public var year: Int16 = 0
    public var limit: Int16 = 0
    public var month: Int8 = 0
    public var day: Int8 = 0
    public var weekday: Int8 = 0
    public var stride: Int8 = 1
}

public extension Recur {
    
    /*
        if r.date >= date then ^r.date
        if r.year < d.year => ^nil

        if r.year == 0
        then n.year = d.year
        else n.year = r.year // r.year > d.year

        if r.month == 0
        then r.month = d.year
        else if r.month < d.month then ++n.year
        else n.month = r.month // r.month > d.month
     
        if r.month < d.month =>
        
     */
    func start(from date: Date, in cal: Calendar = Calendar.current) -> Date? {
        let d = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        var n = DateComponents()
        if year > 0, d.year! < year { return nil }
        if year == 0 {
            n.year = d.year
        } else {
            n.year = Int(year)
        }
        
        if month == 0 {
            n.month = d.month!
        } else if month < d.month! {
            n.year! += 1
        } else {
            n.month = Int(month)
        }
        
        if day == 0 {
            n.day = d.day!
        } else if day < d.day! {
            n.month! += 1
        } else {
            n.day = Int(day)
        }

        return n.date
    }
    
    /**
     If we have a starting/reference date for the bounding span we use it
     to verify any stride > 1 if we have a day-of-week. Otherwise fall back
     to the other match
     */
    func matches(_ date: Date, from ref: Date, in cal: Calendar = Calendar.current) -> Bool {
        guard self.stride > 1, let rdate = start(from: ref, in: cal) else {
            return matches(date, in: cal)
        }
        let delta = (date.julianDay - rdate.julianDay) % (Int(stride) * 7)
        return (delta == 0)
    }

    func matches(_ date: Date, in cal: Calendar? = nil) -> Bool {
        let cal = cal ?? Calendar.current // Calendar(identifier: .gregorian)
        let ymdw = cal.dateComponents([.year, .month, .day, .weekday],
                                      from: date)
        if year > 0, ymdw.year! != year { return false }
        if month > 0, ymdw.month! != month { return false }
        if day > 0, ymdw.day! != day { return false }
        if weekday > 0, weekday != ymdw.weekday! { return false }
        return true
    }
}

public extension Recur {
    static let dels = CharacterSet(charactersIn: "._")
    static let days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    
    init? (_ str: String) {
        
        let argv = str.lowercased().components(separatedBy: Recur.dels)
        
        func iv<I:FixedWidthInteger>(_ ndx: Int, or: I) -> I {
            guard let s = argv[safe: ndx] else { return or }
            return I(s) ?? or
        }
        
        if Recur.days.contains(argv[0]) {
            // Day of week setup
            weekday = Int8(Recur.days.firstIndex(of: argv[0])! + 1)
            if let s = argv.last, s.hasPrefix("%") {
                stride = Int8(s[1...]) ?? 1
            }
        }
        else {
            year = iv(0, or: 0)
            month = iv(1, or: 0)
            day = iv(2, or: 0)
            if let s = argv.last, s.hasPrefix("%") {
                stride = Int8(s[1...]) ?? 1
            }
        }
    }
}

extension String {
    subscript (_ range: CountablePartialRangeFrom<Int>) -> String {
        return String(self[index(startIndex, offsetBy: range.lowerBound)...])
    }
}
