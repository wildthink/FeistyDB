//
//  CalendarTable.swift
//  fdb
//
//  Created by Jason Jobe on 7/23/20.
//  Copyright © 2020 Jason Jobe. All rights reserved.
//
import Foundation
import CSQLite
import FeistyDB

final public class CalendarModule: BaseTableModule {
        
    public enum Column: Int32, ColumnIndex {
        case date, weekday, day, week, month, year,
             julianDay, julianDate, print,
             start, stop, step,
             format
        
        var filterOption: FilterInfo.Option {
            switch self {
                case .date, .year: return .ok
                case .start, .stop: return .ok
                case .step: return .eq_only
                case .format: return .eq_only
                default:
                    return .exclude
            }
        }
    }
    public override var declaration: String {
        "CREATE TABLE x(date, weekday, day, week, month, year, julianDay, julianDate, print, start HIDDEN, stop HIDDEN, step HIDDEN, format HIDDEN)"
    }

    var date_fmt: DateFormatter = DateFormatter()
    var calendar: Calendar = Calendar(identifier: .gregorian)
    var _min: Date = .distantPast
    var _max: Date = .distantFuture
    var step: Calendar.Frequency = .daily

    required init(database: Database, arguments: [String], create: Bool) throws {
//        report (#function, arguments)
        try super.init(database: database, arguments: arguments, create: create)
        // args 0..2 -> module_name, db_name, table_name
        postInit(argv: Array(arguments.dropFirst(3)))
    }
    
    required public init(database: Database, arguments: [String]) throws {
//        report (#function, arguments)
        try super.init(database: database, arguments: arguments, create: false)
        // args 0..2 -> module_name, db_name, table_name
        postInit(argv: Array(arguments.dropFirst(3)))
    }
    
    func postInit(argv: [String]) {
        date_fmt.dateFormat = "yyyy-MM-dd"

        if let val = argv[safe: 0] {
            _min = date_fmt.date(from: val) ?? .distantPast
        }
        if let val = argv[safe: 1] {
            _max = date_fmt.date(from: val) ?? .distantFuture
        }
        if let val = argv[safe: 2] {
            step = Calendar.Frequency.named(val) ?? .daily
        }
//        report (#function, "min:", self._min, "max:", self._max, "step:", self.step)
    }
    
    public override func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        
        guard let info = FilterInfo(&indexInfo, check: { (farg) in
            // Maybe another option being .error or .reject?
            // when we encounter an unknow columen which should NEVER happen!!
            guard let col = Column(rawValue: farg.col_ndx) else { return .exclude }
            return col.filterOption
        })
        else { return .constraint }
        
        if let _ = info.argv.first(where: { !$0.usable }) {
            return .constraint
        }
        
        if info.contains(Column.start) && info.contains(Column.stop) {
            indexInfo.estimatedCost = 2  - (info.contains(Column.step) ? 1 : 0)
            indexInfo.estimatedRows = 1000
        }
        else {
            indexInfo.estimatedRows = 2147483647
        }
        
        if let arg = info.argv.first(where: { $0 == Column.date } ),
           arg.op_str == "=" {
            indexInfo.estimatedRows = 1
            indexInfo.idxFlags = SQLITE_INDEX_SCAN_UNIQUE
        }

        indexInfo.idxNum = add(info)
        Report.print("bestIndex:", info.describe(with: Self.Column.allCases.map { $0.name }))
        return .ok
    }

    public override func openCursor() -> VirtualTableCursor {
        return Cursor(self)
    }
}

extension CalendarModule {
    final class Cursor: BaseTableModule.Cursor<CalendarModule> {
        
        var calendar: Calendar
        var _min: Date
        var _max: Date
        var current: Date?
        var step: Calendar.Frequency = .daily
        var date_fmt: DateFormatter { module.date_fmt }
        var print_fmt: DateFormatter

        public override init(_ vtab: CalendarModule)
        {
            self.calendar = vtab.calendar
            self._min = vtab._min
            self._max = vtab._max
            self.step = vtab.step
            self.current = _min
            self.print_fmt = vtab.date_fmt.copy() as! DateFormatter
            super.init(vtab)
        }

        override func column(_ index: Int32) -> DatabaseValue {
            // "CREATE TABLE x(date, weekday, day, week, month, year, start, stop, step)"
            func dbvalue(_ date: Date, _ comp: Calendar.Component) -> DatabaseValue {
                .integer(Int64(calendar.component(comp, from: date)))
            }
            guard let date = current, let col = Column(rawValue: index) else { return .null }
            switch col {
                case .date:     return .text(date_fmt.string(from: date))
                case .weekday:  return dbvalue(date, .weekday)
                case .day:      return dbvalue(date, .day)
                case .week:     return dbvalue(date, .weekOfYear)
                case .month:    return dbvalue(date, .month)
                case .year:     return dbvalue(date, .year)

                case .julianDay:    return .integer(Int64(date.julianDay))
                case .julianDate:   return .float(date.julianDate)

                case .print:   return .text(print_fmt.string(from: date))

                //  HIDDEN
                case .start:    return .text(date_fmt.string(from: _min))
                case .stop:     return .text(date_fmt.string(from: _max))
                case .step:     return .text(step.name)
                case .format:   return .text(print_fmt.dateFormat)
            }
        }
        
        override func next() {
            _rowid += 1
            current = step.nextDate(from: current, in: calendar) ?? current
        }
                
        override func filter(_ arguments: [DatabaseValue], indexNumber: Int32, indexName: String?) {
            defer { module.clearFilters() }
            let filterInfo = module.filters[Int(indexNumber)]
//            guard let filterInfo = filterInfo ?? module.filters[Int(indexNumber)]
//            else { return }
            _rowid = 1
            
            // DEBUG
            Report.print(#function, indexNumber, "\n", filterInfo.describe(with: Column.allCases.map {String(describing:$0)}, values: arguments))
            
            func date(y: Int64, m: Int, d: Int) -> Date {
                var dateComponents = DateComponents()
                dateComponents.year = Int(y)
                dateComponents.month = m
                dateComponents.day = d
                return calendar.date(from: dateComponents)!
            }
            
            // FIXME;
            // select start, stop, datefmt('E', date), * from cal where year >= 2020 and month = 10 and (weekday = 2 and weekday = 3) limit 10;
            // DOES NOT CONSTRAIN BY YEAR
            for farg in filterInfo.argv {
                switch (Column(rawValue: farg.col_ndx), arguments[Int(farg.arg_ndx)]) {
                    case (.start, let .text(argv)):
                        _min  = date_fmt.date(from: argv) ?? _min
                    case (.stop, let .text(argv)):
                        _max  = date_fmt.date(from: argv) ?? _max
                    case (.step, let .text(argv)):
                        step = Calendar.Frequency.named(argv) ?? step
              
                    case (.year, let .integer(year))
                            where [">=", ">"].contains(farg.op_str):
                        let min_date = date(y: year, m: 1, d: 1) // Jan 1
                        if min_date > _min { _min = min_date }

                    case (.year, let .integer(year))
                            where ["<=", "<"].contains(farg.op_str):
                        let max_date = date(y: year, m: 12, d: 31) // Dec 32
                        if max_date < _max { _max = max_date }

                    case (.year, let .integer(year)) where farg.op_str == "=":
                        let min_date = date(y: year, m: 1, d: 1) // Jan 1
                        if min_date > _min { _min = min_date }

                        let max_date = date(y: year, m: 12, d: 31) // Dec 32
                        if max_date < _max { _max = max_date }
                        
                    case (.date,  let .text(argv)):
                        guard let date = date_fmt.date(from: argv)  else { continue }
                        (_min, _max) = cmpBounds(farg.op_str, date, in: (_min, _max))

                    case (.format,  let .text(argv)):
                        print_fmt.dateFormat = argv

                    default:
                        break
                }
            }
            current = filterInfo.isDescending ? _max : _min
            
            // DEBUG
            Report.print( filterInfo.describe(with: Column.allCases.map { String(describing:$0)}, values: arguments))
            Report.print(self._min, self._max)

        }
        
        override var eof: Bool {
            // HARD LIMIT of total days for 1000 year span is 360_500
            if let date = current, date > _max || _rowid > 360_500 {
                return true
            }
            return false
        }
    }
}
