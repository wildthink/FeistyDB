/*
 *  Copyright (C) 2015, 2016 Feisty Dog, LLC
 *  All Rights Reserved
 */

import Foundation

/// A type that may be serialized to and deserialized from a database.
///
/// This is a more general method for database storage than `ParameterBindable` and `ColumnConvertible`
/// because it allows types to customize their behavior based on the database value's data type. 
/// A database value's data type is the value returned by the `sqlite3_column_type()` before any
/// type conversions have taken place.
///
/// - note: Columns in SQLite have a type affinity (declared type) while stored values have an 
/// individual storage class/data type.  There are rules for conversion which are documented
/// at [Datatypes In SQLite Version 3](https://sqlite.org/datatype3.html).
///
/// For example, `NSNumber` can choose what to store in the database based on the boxed value:
///
/// ```swift
/// extension NSNumber: DatabaseSerializable {
///     public func serialized() -> DatabaseValue {
///         switch CFNumberGetType(self as CFNumber) {
///         case .sInt8Type, .sInt16Type, .sInt32Type, .charType, .shortType, .intType,
///              .sInt64Type, .longType, .longLongType, .cfIndexType, .nsIntegerType:
///             return DatabaseValue.integer(self.int64Value)
///
///         case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
///             return DatabaseValue.float(self.doubleValue)
///         }
///     }
///
///     public static func deserialize(from value: DatabaseValue) throws -> Self {
///         switch value {
///         case .integer(let i):
///             return self.init(value: i)
///         case .float(let f):
///             return self.init(value: f)
///         default:
///             throw DatabaseError.dataFormatError("\(value) is not a number")
///         }
///     }
/// }
/// ```
public protocol DatabaseSerializable: ParameterBindable {
	/// Returns a serialized value of `self`.
	///
	/// - returns: A serialized value representing `self`
	func serialized() -> DatabaseValue

	/// Deserializes and returns `value` as `Self`.
	///
	/// - parameter value: A serialized value of `Self`
	///
	/// - throws: An error if `value` contains an illegal value for `Self`
	///
	/// - returns: An instance of `Self`
	static func deserialize(from value: DatabaseValue) throws -> Self
}

extension DatabaseSerializable {
	public func bind(to stmt: SQLitePreparedStatement, parameter idx: Int32) throws {
		try serialized().bind(to: stmt, parameter: idx)
	}
}

extension Row {
	/// Returns the value of the column at `index`.
	///
	/// - note: Column indexes are 0-based.  The leftmost column in a row has index 0.
	///
	/// - requires: `index >= 0`
	/// - requires: `index < self.columnCount`
	///
	/// - parameter index: The index of the desired column
	///
	/// - throws: An error if the column contains an illegal value
	///
	/// - returns: The column's value
	public func value<T: DatabaseSerializable>(at index: Int) throws -> T {
		return try T.deserialize(from: value(at: index))
	}

	/// Returns the value of column `name`.
	///
	/// - parameter name: The name of the desired column
	///
	/// - throws: An error if the column wasn't found or contains an illegal value
	///
	/// - returns: The column's value
	public func value<T: DatabaseSerializable>(named name: String) throws -> T {
		return try T.deserialize(from: value(named: name))
	}
}

extension DatabaseSerializable where Self: NSCoding {
	public func serialized() -> DatabaseValue {
		return .blob(NSKeyedArchiver.archivedData(withRootObject: self))
	}

	public static func deserialize(from value: DatabaseValue) throws -> Self {
		switch value {
		case .blob(let b):
			guard let result = NSKeyedUnarchiver.unarchiveObject(with: b) as? Self else {
				throw DatabaseError.dataFormatError("\(value) is not a valid instance of \(Self.self)")
			}
			return result
		default:
			throw DatabaseError.dataFormatError("\(value) is not a blob")
		}
	}
}

extension NSNumber: DatabaseSerializable {
	public func serialized() -> DatabaseValue {
		switch CFNumberGetType(self as CFNumber) {
		case .sInt8Type, .sInt16Type, .sInt32Type, .charType, .shortType, .intType,
		     .sInt64Type, .longType, .longLongType, .cfIndexType, .nsIntegerType:
			return DatabaseValue.integer(self.int64Value)

		case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
			return DatabaseValue.float(self.doubleValue)
		}
	}

	public static func deserialize(from value: DatabaseValue) throws -> Self {
		switch value {
		case .integer(let i):
			return self.init(value: i)
		case .float(let f):
			return self.init(value: f)
		default:
			throw DatabaseError.dataFormatError("\(value) is not a number")
		}
	}
}

extension NSNull: DatabaseSerializable {
	public func serialized() -> DatabaseValue {
		return .null
	}

	public static func deserialize(from value: DatabaseValue) throws -> Self {
		switch value {
		case .null:
			return self.init()
		default:
			throw DatabaseError.dataFormatError("\(value) is not null")
		}
	}
}
