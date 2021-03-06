//
//  FeistyVtabExtensions.swift
//  fdb
//
//  Created by Jason Jobe on 8/19/20.
//

import Foundation
import CSQLite
import FeistyDB

public protocol ColumnIndex: CaseIterable {
    var rawValue: Int32 { get }
    var name: String { get }
    init? (name: String)
}

public extension ColumnIndex {
    var name: String { return "\(self)" }
    init? (name: String) {
        for c in Self.allCases where name == c.name {
            self = c
            return
        }
        return nil
    }
}

// Extenstion to interface w/ SeriesModule

public func == <C: ColumnIndex>(lhs: FilterArg, rhs: C) -> Bool {
    lhs.col_ndx == rhs.rawValue
}

extension FilterInfo {
    func contains<C: ColumnIndex>(_ col: C) -> Bool {
        argv.contains(where: { $0.col_ndx == col.rawValue} )
    }
}


open class BaseTableModule: VirtualTableModule {
    
    public enum Column: Int32, ColumnIndex {
        case value, start, stop, step
    }
    public var filters: [FilterInfo] = []

    public required init(database: Database, arguments: [String], create: Bool) throws {
        Report.print (#function, arguments)
    }
    
    public required init(database: Database, arguments: [String]) throws {
        Report.print (#function, arguments)
    }
    
    open func add(_ filter: FilterInfo) -> Int32 {
        filter.key = Int32(filters.count)
        filters.append(filter)
        return filter.key
    }
    open func clearFilters() {
        filters.removeAll()
    }
    
    open var declaration: String {
        "CREATE TABLE x(value)"
    }
    
    open var options: Database.VirtualTableModuleOptions {
        return [.innocuous]
    }
    
    open func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        return .ok
    }
    
    open func openCursor() -> VirtualTableCursor {
        return Cursor(self)
    }
}

extension BaseTableModule {
    open class Cursor<M: BaseTableModule>: VirtualTableCursor {
        
        public let module: M
//        public let filterInfo: FilterInfo?
        public var _rowid: Int64 = 0
        open var eof: Bool { true }

        public var isDescending: Bool = false

//        public var isDescending: Bool { filterInfo?.isDescending ?? false }
        
//        public init(_ module: M, filter: FilterInfo?) {
//            self.module = module
//            self.filterInfo = filter
//        }

        public init(_ module: M) {
            self.module = module
        }

        open func column(_ index: Int32) throws -> DatabaseValue {
            .null
        }
        
        open func next() throws {
            _rowid += 1
        }
        
        open func rowid() throws -> Int64 {
            _rowid
        }
        
        open func filter(_ arguments: [DatabaseValue], indexNumber: Int32, indexName: String?) throws {
        }
    }
}

// MARK: FilterInfo

public class FilterInfo: CustomStringConvertible {
    public var key: Int32 = 0
    public var argv: [FilterArg] = []
    public var columnsUsed: UInt64 = 0
    public var isDescending: Bool = false
    
    public func contains(_ col: Int32) -> Bool {
        argv.contains(where: { $0.col_ndx == col} )
    }
    
    public func describe(with cols: [String], values: [Any] = []) -> String {
        var str = "Filter[\(key)] (" // + String(columnsUsed, radix: 2) + " "
        for arg in argv {
            Swift.print(arg.describe(with: cols, values: values),
                        separator: ",", terminator: " ", to: &str)
        }
        Swift.print(")", separator: "", terminator: "", to: &str)
        return str
    }
    
    public var description: String {
        var str = "Filter[\(key)] (" // + String(columnsUsed, radix: 2) + " "
        for arg in argv {
            Swift.print(arg.description,
                        separator: ",", terminator: " ", to: &str)
        }
        Swift.print(")", separator: "", terminator: "", to: &str)
        return str
    }
}

public extension FilterInfo {
    
    enum Option { case ok, eq_only, required, hidden, exclude }
    typealias ConstraintCheck = (FilterArg) -> Option
    
    convenience init? (_ indexInfo: inout sqlite3_index_info, check: ConstraintCheck? = nil) {
        
        self.init()

        // Inputs
        let constraintCount = Int(indexInfo.nConstraint)
        let constraints = UnsafeBufferPointer<sqlite3_index_constraint>(
            start: indexInfo.aConstraint, count: constraintCount)
        
        let check = check ?? { (_) in .ok }
        var argc: Int32 = 1
        
        for i in 0 ..< constraintCount {
            let constraint = constraints[i]
            
            let farg = FilterArg(arg: argc - 1, col: constraint.iColumn, op: constraint.op, usable: (constraint.usable != 0))

            switch check(farg) {
                case .required:
                    if (1 != constraint.usable) { return nil }
                case .exclude:
                    continue
                case .ok:
                    break
                case .hidden:
                    break
                case .eq_only:
                    if (1 != constraint.usable) && constraint.op != SQLITE_INDEX_CONSTRAINT_EQ {
                        return nil
                    }
            }
            argv.append(farg)
            // Outputs
            indexInfo.aConstraintUsage[i].argvIndex = argc
            // NOTE: Consider omit = 1 if column is HIDDEN
            // indexInfo.aConstraintUsage[i].omit = 1
            argc += 1
        }
        
        let orderByCount = Int(indexInfo.nOrderBy)
        let orderBy = UnsafeBufferPointer<sqlite3_index_orderby>(start: indexInfo.aOrderBy, count: orderByCount)
        
        if orderByCount == 1 {
            if orderBy[0].desc == 1 {
                isDescending = true
            }
            // Output
            indexInfo.orderByConsumed = 1
        }
        self.columnsUsed = indexInfo.colUsed
    }
    
}

// MARK: FilterArg
public struct FilterArg: CustomStringConvertible, Equatable {
    
    public let arg_ndx: Int32
    public let col_ndx: Int32
    public let op: UInt8
    public let usable: Bool
    
    public init(arg: Int32, col: Int32, op: UInt8, usable: Bool) {
        self.arg_ndx = arg
        self.col_ndx = col
        self.op = op
        self.usable = usable
    }
    
    init<C: ColumnIndex>(arg: Int32, col: C, op: UInt8, usable: UInt8) {
        self.init(arg: arg, col: col.rawValue, op: op, usable: usable != 0)
    }

    public var description: String  { "col[\(col_ndx)] \(op_str) argv[\(arg_ndx)])" }
    public var op_str: String       { FilterArg.op_str(self.op) }
    
    public func describe(with cols: [String], values: [Any] = []) -> String {
        let ndx = Int(col_ndx)
        let col = (ndx < cols.count ? cols[ndx] : "col[\(ndx)]")
        let a_ndx = Int(arg_ndx)
        let arg = (a_ndx < values.count ? values[a_ndx] : "argv[\(a_ndx)]")
        let use = usable ? "*" : ""
        return "\(use)\(col) \(op_str) \(arg)"
    }
    
    public static func op_str(_ op: UInt8) -> String {
        
        switch Int32(op) {
            case SQLITE_INDEX_CONSTRAINT_EQ: return "="
            case SQLITE_INDEX_CONSTRAINT_GT: return ">"
            case SQLITE_INDEX_CONSTRAINT_LE: return "<="
            case SQLITE_INDEX_CONSTRAINT_LT: return "<"
            case SQLITE_INDEX_CONSTRAINT_GE: return ">="
            case SQLITE_INDEX_CONSTRAINT_MATCH: return "MATCH"
            case SQLITE_INDEX_CONSTRAINT_LIKE: return "LIKE"
            case SQLITE_INDEX_CONSTRAINT_GLOB: return "GLOB"
            case SQLITE_INDEX_CONSTRAINT_REGEXP: return "REGEX"
            case SQLITE_INDEX_CONSTRAINT_NE: return "!="
            case SQLITE_INDEX_CONSTRAINT_ISNOT: return "IS NOT"
            case SQLITE_INDEX_CONSTRAINT_ISNOTNULL: return "IS NOT NULL"
            case SQLITE_INDEX_CONSTRAINT_ISNULL: return "IS NULL"
            case SQLITE_INDEX_CONSTRAINT_IS: return "IS"
            case SQLITE_INDEX_CONSTRAINT_FUNCTION: return "f()"
            default:
                return "<op>"
        }
    }
}

