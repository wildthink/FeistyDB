//
//  CalendarVTable.swift
//  fdb
//
//  Created by Jason Jobe on 8/17/20.
//
import Foundation
import CSQLite
import FeistyDB

public final class SeriesModule: BaseTableModule {

    public enum Column: Int32, ColumnIndex, CaseIterable {
        case value, start, stop, step
        var filterOption: FilterInfo.Option {
            switch self {
                case .start, .stop: return .ok
                case .step: return .eq_only
                default:
                    return .ok
            }
        }

    }

    var _min: Int64 = 0
    var _max: Int64 = .max
    var step: Int64 = 1

    public override var declaration: String {
        "CREATE TABLE series (value,start hidden,stop hidden,step hidden)"
    }
    
    required init(database: Database, arguments: [String], create: Bool) throws {
        try super.init(database: database, arguments: arguments, create: create)
        // args 0..2 -> module_name, db_name, table_name
        postInit(argv: Array(arguments.dropFirst(3)))
    }
    
    required public init(database: Database, arguments: [String]) throws {
        try super.init(database: database, arguments: arguments, create: false)
        // args 0..2 -> module_name, db_name, table_name
        postInit(argv: Array(arguments.dropFirst(3)))
    }
    
    func postInit(argv: [String]) {
        _min = argv[safe: 0]?.int64Value ?? 0
        _max = argv[safe: 1]?.int64Value ?? .max
        step = argv[safe: 2]?.int64Value ?? 1
    }
    
    public override func openCursor() -> VirtualTableCursor {
        return Cursor(self)
    }

    public override func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        
        guard let info = FilterInfo(&indexInfo) else { return .constraint }
//        if info.contains(Column.start) && info.contains(Column.stop) {
//            indexInfo.estimatedCost = 2  - (info.contains(Column.step) ? 1 : 0)
//            indexInfo.estimatedRows = 1000
//        }
//        else {
//            indexInfo.estimatedRows = Int64.max // 2147483647
//        }
        
        if let _ = info.argv.first(where: { !$0.usable }) {
            return .constraint
        }

        if let arg = info.argv.first(where: { $0 == Column.value } ),
           arg.op_str == "=" {
            indexInfo.estimatedRows = 1
            indexInfo.idxFlags = SQLITE_INDEX_SCAN_UNIQUE
        }

        indexInfo.idxNum = add(info)
        return .ok
    }
}

extension SeriesModule {
    final class Cursor: BaseTableModule.Cursor<SeriesModule> {
        
        let max_rows = 100_000_000 // Safety Net b/c default Int.max is WAY TOO BIG
        var _value: Int64 = 0
        var _min: Int64 = 0
        var _max: Int64 = 0
        var _step: Int64 = 0
        
        public override init(_ vtab: SeriesModule)
        {
            self._min = vtab._min
            self._max = vtab._max
            self._step = vtab.step
            self._value = _min
            super.init(vtab)
        }

        override func column(_ index: Int32) -> DatabaseValue {
            let col = Column(rawValue: index)
            switch col {
                case .value: return .integer(_value)
                case .start: return .integer(_min)
                case .stop:  return .integer(_max)
                case .step:  return .integer(_step)
                default:     return nil
            }
        }
        
        override func next() {
            _value += (isDescending ? -_step : _step)
            _rowid += 1
        }
        override var eof: Bool {
            guard _rowid <= max_rows else { return true }
            return isDescending ? (_value < _min) : (_value > _max)
        }

        override func filter(_ arguments: [DatabaseValue], indexNumber: Int32, indexName: String?) {
            defer { module.clearFilters() }
            let filterInfo = module.filters[Int(indexNumber)]

            // DEBUG
//            Report.print(
//                filterInfo.describe(with: Column.allCases.map {String(describing:$0)},
//                                           values: arguments))
       
            for farg in filterInfo.argv {
                let col = Column(rawValue: farg.col_ndx)
                guard let arg = arguments[Int(farg.arg_ndx)].int64Value else { continue }
                
                switch (col, farg.op_str) {
                    case (.start, "="),
                         (.start, ">="),
                         (.start, ">"):
                        _min  = arg
                    case (.stop, "="),
                         (.stop, "<="),
                         (.stop, "<"):
                        _max  = arg
                    case (.step, "="):
                        _step = arg
                        
                    case (.value, "="):
                        (_min, _max) = (arg, arg)
                    case (.value, ">="), (.value, ">"):
                        (_min, _max) = (arg, _max)
                    case (.value, "<="), (.value, "<"):
                        (_min, _max) = (_min, arg)

                    default:
                        break
                }
            }

            /*
            for farg in filterInfo.argv.reversed() {
                switch (Column(rawValue: farg.col_ndx), arguments[Int(farg.arg_ndx)]) {
                    case (.start, let DatabaseValue.integer(arg)): _min  = arg
                    case (.stop,  let DatabaseValue.integer(arg)): _max  = arg
                    case (.step,  let DatabaseValue.integer(arg)): _step = arg

                    case (.value, let DatabaseValue.integer(arg)):
                        (_min, _max) = cmpBounds(farg.op_str, arg, in: (_min, _max))

                    default:
                        break
                }
            }
            */
            
            if arguments.contains(where: { return $0 == .null ? true : false }) {
                _min = 1
                _max = 0
            }
            
            _value = isDescending ? _max : _min
            if isDescending && _step > 0 {
                _value -= (_max - _min) % _step
            }
        }
    }
}
