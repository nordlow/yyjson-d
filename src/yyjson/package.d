/** D-wrapper around `yyjson` mimicing `std.json`.
 */
module yyjson;

import std.mmfile : MmFile;
import yyjson.result : Result;

@safe:

/++ "Immutable" JSON Document.
 +
 +  TODO: Turn into a result type being either a non-null pointer or an error type.
 +  Descriminator can be the least significant bit.
 +
 +  See_Also: https://en.wikipedia.org/wiki/Mmap
 +/
struct Document(Char = const(char), bool memoryMapped = false) {
	@disable this(this);

	static if (memoryMapped) {
		import std.mmfile : MmFile;
		this(const(yyjson_doc)* doc, MmFile mmf) @trusted in(doc) {
			_doc = doc;
			_mmf = mmf;
			_store = cast(Char[])mmf[];
		}
	} else {
		this(const(yyjson_doc)* doc, Char[] dat = null) in(doc) {
			_doc = doc;
			_store = dat;
		}
	}

pure nothrow @nogc:

	~this() @trusted {
		auto mdoc = cast(yyjson_doc*)_doc;
		if (!_doc)
			return;
		if (_doc.str_pool)
			(cast(FreeFn)(_doc.alc.free))(mdoc.alc.ctx, mdoc.str_pool);
		(cast(FreeFn)mdoc.alc.free)(mdoc.alc.ctx, mdoc);
		// uncommented because ASan complains about this: _doc.alc = typeof(_doc.alc).init;
	}

/+pragma(inline, true):+/

	bool opCast(T : bool)() const scope => _doc !is null;

	bool opEquals(in typeof(this) rhs) const scope => _store == rhs._store; // prevent complation error with Object.opEquals for `_mmf`

	/++ Returns: Root value or `null` if `_doc` is `null`. +/
	const(Value) root() const scope => typeof(return)(_doc ? _doc.root : null);

	/++ Returns: Total number of bytes read (nonzero). +/
	size_t byteCount() const scope => _doc.dat_read;

	/++ Returns: Total number of (node) values read (nonzero). +/
	size_t valueCount() const scope => _doc.val_read;
	private alias nodeCount = valueCount;

	/++ Returns: Original source data. +/
	Char[] data() const return scope => _store;
	/// ditto
	alias source = data;

private:
	const(yyjson_doc)* _doc; // non-null
	static if (memoryMapped)
		MmFile _mmf;
	Char[] _store; // data store
}

/++ Type of a JSON value (3 bit). +/
enum ValueType : yyjson_type {
	/** No type, invalid. */
	NONE = YYJSON_TYPE_NONE,
	/** Raw string type, no subtype. */
	RAW = YYJSON_TYPE_RAW,
	/** Null type: `null` literal, no subtype. */
	NULL = YYJSON_TYPE_NULL,
	/** Boolean type, subtype: TRUE, FALSE. */
	BOOL = YYJSON_TYPE_BOOL,
	/** Number type, subtype: UINT, SINT, REAL. */
	NUM = YYJSON_TYPE_NUM,
	/** String type, subtype: NONE, NOESC. */
	STR = YYJSON_TYPE_STR,
	/** Array type, no subtype. */
	ARR = YYJSON_TYPE_ARR,
	/** Object type, no subtype. */
	OBJ = YYJSON_TYPE_OBJ,
}
///
alias JSONValueType = ValueType;

/++ Type of a JSON value being a superset of `std.json.ValueType`.
 + `std.json` compliance.
 +/
enum JSONType : byte {
    null_,
    string,
    integer,
    uinteger,
    float_,
    array,
    object,
    true_,
    false_,
	raw, // Extended.
	none, // Extended.
}

/++ Constant JSON Value (Reference Pointer). +/
struct Value {
	import core.stdc.string : strlen;

	private yyjson_val* _val;

pure nothrow @property:
	this(const(yyjson_val)* val) const scope nothrow @nogc @trusted {
		_val = cast(yyjson_val*)val;
	}

	/// For `std.json` compliance. Allocates with the GC!
	const(Value)[] arraySlice() const /+return scope+/ in(type == ValueType.ARR) {
		const length = yyjson_arr_size(_val);
		typeof(return) res;
		res.reserve(length);
		foreach (const idx; 0 .. length)
			res ~= const(Value)(yyjson_arr_get(_val, idx));
		return res;
	}

@nogc:

	/++ TODO: Get value as an array. +/

	/++ Get value as a {range|view} over array elements. +/
	auto arrayRange() const in(type == ValueType.ARR) {
		static struct Result {
		private:
			yyjson_arr_iter _iter;
			const(yyjson_val)* _val;
			size_t _length;
		scope pure nothrow @safe @nogc:
		/+pragma(inline, true):+/
			@disable this(this);
			this(const(yyjson_val)* arr) @trusted {
				_length = yyjson_arr_size(arr);
				yyjson_arr_iter_init(cast()arr, &_iter);
				nextFront();
			}
			void nextFront() @trusted {
				if (yyjson_arr_iter_has_next(&_iter))
					_val = yyjson_arr_iter_next(&_iter);
				else
					_val = null;
			}
		public:
			void popFront() in(!empty) {
				nextFront();
				_length -= 1;
			}
		const @property:
			version(none) // TODO: Support
			/** Returns the element at the specified position in this array.
				Returns NULL if array is NULL/empty or the index is out of bounds.
				@warning This function takes a linear search time if array is not flat.
				For example: `[1,{},3]` is flat, `[1,[2],3]` is not flat. */
			Value at(size_t i) const {
				return typeof(return)(yyjson_arr_get(_val, i));
			}
			// Value opIndex(in size_t i) return scope {
			// }
			// Value opSlice(in size_t i, in size_t j) return scope {
			// }
			size_t length() => _length; // for the sake of `std.traits.hasLength`
			bool empty() => _val is null;
			const(Value) front() return scope in(!empty) => typeof(return)(_val);
		}
		return Result(_val);
 	}
	alias array = arrayRange; // `std.traits` compliance

	/++ Object key type. +/
	alias Key = Value;

	/++ Object value type. +/
	alias Value = .Value;

	/++ Check if element with key `key` is stored/contained. +/
	const(Value) opBinaryRight(.string op)(in char[] key) const return scope @trusted if (op == "in") {
		return typeof(return)(yyjson_obj_getn(cast(yyjson_val*)_val, key.ptr, key.length));
	}

	/++ Get element value with key `key`. +/
	const(Value) opIndex(in char[] key) const return scope @trusted {
		return typeof(return)(yyjson_obj_getn(cast(yyjson_val*)_val, key.ptr, key.length));
	}

	/++ TODO: Get value as an object. +/

	/++ Get value as a {range|view} over object elements (key-values). +/
	auto objectRange() const in(type == ValueType.OBJ) {
		/++ Object key-value (element) type. +/
		struct KeyValue {
			Key key; ///< Key part of object element.
			Value value; ///< Value part of object element.
		}
		static struct Result {
		private:
			yyjson_obj_iter _iter;
			const(yyjson_val)* _key;
			size_t _length;
		/+pragma(inline, true):+/
		scope pure @safe:
			public const(Value) opIndex(in char[] key) @property return scope {
				auto hit = find(key);
				if (!hit)
					throw new Exception(("Key " ~ key ~ " not found").idup);
				return hit;
			}
		nothrow @nogc:
			@disable this(this);
			this(const(yyjson_val)* obj) @trusted {
				_length = yyjson_obj_size(obj);
				yyjson_obj_iter_init(cast()obj, &_iter);
				nextFront();
			}
			void nextFront() @trusted {
				if (yyjson_obj_iter_has_next(&_iter))
					_key = yyjson_obj_iter_next(&_iter);
				else
					_key = null;
			}
		public:
			void popFront() in(!empty) {
				nextFront();
				_length -= 1;
			}
		@property:
			/// Try to find object element with key `key`.
			const(Value) find(in char[] key) return scope {
				while (!empty) {
					if (frontKey.isString && frontKey.str == key)
						return frontValue;
					popFront();
				}
				return typeof(return).init;
			}
		const:
			size_t length() => _length; // for the sake of `std.traits.hasLength`
			bool empty() => _key is null;
			const(Key) frontKey() return scope in(!empty) => typeof(return)(_key);
			const(Value) frontValue() return scope @trusted in(!empty) {
				return typeof(return)(yyjson_obj_iter_get_val(cast(yyjson_val*)_key));
			}
			const(KeyValue) front() return scope => typeof(return)(frontKey, frontValue);
		}
		return Result(_val);
 	}
	alias orderedObject = objectRange; // `std.json` compliance
	alias object = objectRange; // `std.traits` compliance
	alias byKeyValue = objectRange; // `std.traits` compliance

@property const scope nothrow:
/+pragma(inline, true):+/

	/++ Get length of `this` as an array. +/
	private size_t arrayLength() in(type == ValueType.ARR) => yyjson_arr_size(_val);

	/++ Get length of `this` as an object. +/
	private size_t objectLength() in(type == ValueType.OBJ) => yyjson_obj_size(_val);

	/++ Value getters. TODO: These should return result types or throw +/

	/++ Get value as a boolean. +/
	bool boolean() @trusted in(type == ValueType.BOOL) => unsafe_yyjson_get_bool(cast(yyjson_val*)_val);

	/++ Get value as a signed integer number. +/
	long integer() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_SINT)) => _val.uni.i64;

	/++ Get value as an unsigned integer number. +/
	ulong uinteger() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_UINT)) => _val.uni.u64;

	/++ Get value as a floating point number. +/
	double floating() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_REAL)) => _val.uni.f64;
	/// ditto
	alias float_ = floating;

	/++ Get value as a null-terminated C-style string. +/
	const(char)* cstr() @trusted in(type == ValueType.STR) => _val.uni.str;

	/++ Get value as a D-style character slice (string). +/
	const(char)[] str() @trusted => cstr[0..strlen(cstr)];
	/// ditto
	private alias string = str;

nothrow:
	bool opCast(T : bool)() scope => _val !is null;

	/++ Get type. +/
	ValueType type() scope {
		if (_val is null)
			return ValueType.NONE;
		return cast(typeof(return))(_val.tag & YYJSON_TYPE_MASK);
	}

	/// `std.json` compliance
	JSONType type_std() scope {
		final switch (type) {
		case ValueType.NONE:
			return typeof(return).none;
		case ValueType.RAW:
			return typeof(return).raw;
		case ValueType.NULL:
			return typeof(return).null_;
		case ValueType.BOOL:
			assert(0, "TODO: Read SUB_TYPE");
		case ValueType.NUM:
			assert(0, "TODO: Read SUB_TYPE");
		case ValueType.STR:
			return typeof(return).string;
		case ValueType.ARR:
			return typeof(return).array;
		case ValueType.OBJ:
			return typeof(return).object;
		}
	}

	/++ Type predicates: +/

	/++ Returns: `true` iff `this` has value `none` (being uninitialized). +/
	bool is_none() => _val is null;
	alias isNone = is_none;

	/++ Returns: `true` iff `this` has value `null`. +/
	bool is_null() => (_val.tag == (YYJSON_TYPE_NULL)) != 0;
	alias isNull = is_null;

	/++ Returns: `true` iff `this` has value `false`. +/
	bool is_false() => (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_FALSE));
	alias isFalse = is_false;

	/++ Returns: `true` iff `this` has value `true`. +/
	bool is_true() => (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_TRUE));
	alias isTrue = is_true;

	/++ Returns: `true` iff `this` is a string. +/
	bool is_string() => (_val.tag & (YYJSON_TYPE_STR)) != 0;
	alias isString = is_string;

	/++ Returns: `true` iff `this` is an array. +/
	bool is_array() => (_val.tag & (YYJSON_TYPE_ARR)) != 0;
	alias isArray = is_array;

	/++ Returns: `true` iff `this` is a flat array. +/
	bool is_flat_array() @trusted => is_array && unsafe_yyjson_arr_is_flat(_val);
	alias isFlatArray = is_flat_array;

	/++ Returns: `true` iff `this` is an object. +/
	bool is_object() => (_val.tag & (YYJSON_TYPE_OBJ)) != 0;
	alias isObject = is_object;

}
alias JSONValue = Value; // `std.json` compliance

/++ Read flag.
 +  See: `yyjson_read_flag` in yyjson.h.
 +/
enum ReadFlag : yyjson_read_flag {
	NOFLAG = YYJSON_READ_NOFLAG,
	INSITU = YYJSON_READ_INSITU,
	STOP_WHEN_DONE = YYJSON_READ_STOP_WHEN_DONE,
	ALLOW_TRAILING_COMMAS = YYJSON_READ_ALLOW_TRAILING_COMMAS,
	ALLOW_COMMENTS = YYJSON_READ_ALLOW_COMMENTS,
	ALLOW_INF_AND_NAN = YYJSON_READ_ALLOW_INF_AND_NAN,
	NUMBER_AS_RAW = YYJSON_READ_NUMBER_AS_RAW,
	ALLOW_INVALID_UNICODE = YYJSON_READ_ALLOW_INVALID_UNICODE,
	BIGNUM_AS_RAW = YYJSON_READ_BIGNUM_AS_RAW,
}

/++ Read (error) code.
 +  See: `yyjson_read_code` in yyjson.h.
 +/
enum ReadCode : yyjson_read_code {
	SUCCESS = YYJSON_READ_SUCCESS,
	ERROR_INVALID_PARAMETER = YYJSON_READ_ERROR_INVALID_PARAMETER,
	ERROR_MEMORY_ALLOCATION = YYJSON_READ_ERROR_MEMORY_ALLOCATION,
	ERROR_EMPTY_CONTENT = YYJSON_READ_ERROR_EMPTY_CONTENT,
	ERROR_UNEXPECTED_CONTENT = YYJSON_READ_ERROR_UNEXPECTED_CONTENT,
	ERROR_UNEXPECTED_END = YYJSON_READ_ERROR_UNEXPECTED_END,
	ERROR_UNEXPECTED_CHARACTER = YYJSON_READ_ERROR_UNEXPECTED_CHARACTER,
	ERROR_JSON_STRUCTURE = YYJSON_READ_ERROR_JSON_STRUCTURE,
	ERROR_INVALID_COMMENT = YYJSON_READ_ERROR_INVALID_COMMENT,
	ERROR_INVALID_NUMBER = YYJSON_READ_ERROR_INVALID_NUMBER,
	ERROR_INVALID_STRING = YYJSON_READ_ERROR_INVALID_STRING,
	ERROR_LITERAL = YYJSON_READ_ERROR_LITERAL,
	ERROR_FILE_OPEN = YYJSON_READ_ERROR_FILE_OPEN,
	ERROR_FILE_READ = YYJSON_READ_ERROR_FILE_READ,
}

/++ Read error.
 +  Same memory layout as `yyjson_read_err`.
 +/
struct ReadError {
    /** Error code, see `yyjson_read_code` for all possible values. */
	ReadCode code;
    /** Error message, constant, no need to free (NULL if success). */
    const(char)* msg;
    /** Error byte position for input data (0 if success). */
    size_t pos;
}

struct Options {
	enum none = typeof(this).init;
	enum allowAll = typeof(this)(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE | ReadFlag.ALLOW_COMMENTS | ReadFlag.ALLOW_INF_AND_NAN);
	private yyjson_read_flag _flag;
	bool mutable;
}
alias JSONOptions = Options; // `std.json` compliance

/++ Parse JSON Document from `path`.
	TODO: Add options for allocation mechanism and immutablity.
 +/
Result!(Document!(Char, memoryMapped), ReadError)
readJSONDocument(Char = const(char), bool memoryMapped = false)(in FilePath path, in Options options = Options.none) /+nothrow @nogc+/ @trusted /+@reads_from_file+/ {
	static if (memoryMapped) {
		return parseJSONDocumentMmap(new MmFile(path), options: options);
	} else {
		/+ Uses `read` instead of `readText` as `yyjson` verifies Unicode.
		   See_Also: `ALLOW_INVALID_UNICODE`. +/
		import std.file : read;
		const data = cast(const(char)[])path.str.read();
		return parseJSONDocument(data, options: options);
	}
}

@safe version(yyjson_benchmark) unittest {
	import std.path : buildPath;
	import std.file : exists;
	const fn = FilePath("5MB-min.json");
	const path = FilePath(homeDir.str.buildPath(fn.str));
	if (!path.str.exists)
		return;
	alias Char = const(char);
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE));
}

@safe version(yyjson_benchmark) unittest {
	import std.path : buildPath;
	import std.file : exists;
	const fn = FilePath("metaModel.json");
	const path = FilePath(homeDir.str.buildPath(fn.str));
	if (!path.str.exists)
		return;
	alias Char = const(char);
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE), printElements: true);
}

/++ Convert tree sitter meta model `mmd` to D code. +/
string convertTreeSitterMetaModelToDCode(const Value mmd) {
	typeof(return) res;
	foreach (const section; mmd.object) {
		import std.stdio;
		writeln(section.key.string, " => ", section.value.type);
		switch (section.key.string) {
		case "metadata":
			break;
		case "requests":
		case "notifications":
		case "structures":
		case "enumerations":
		case "typeAliases":
			foreach (const i; section.value.array) {
				writeln("- ", i, " of type ", i.type);
				foreach (const p1; i.objectRange) { // property
					writeln("  - ", p1.key.string, " => ", p1.value, " of type ", p1.value.type);
				}
			}
			break;
		default:
			break;
		}
	}
	return res;
}

version(yyjson_benchmark) {
	import std.datetime.stopwatch : StopWatch, AutoStart, Duration;

	private void benchmark(Char = const(char), bool memoryMapped = false)(const FilePath path, Options options = Options.init, bool printElements = false) {
		auto sw = StopWatch(AutoStart.yes);
		const docR = path.readJSONDocument!(Char, memoryMapped)(options);
		const dur = sw.peek;
		if (printElements)
			(*docR).root.convertTreeSitterMetaModelToDCode();
		const mbps = (*docR)._store.length.bytesPer(dur) * 1e-6;
		import std.stdio : writeln;
		const type = memoryMapped ? " memory mapped" : "";
		if (docR) {
 			writeln(`Parsing`, type, " ", path, ` of size `, (*docR)._store.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to SUCCEED, options: ", options);
		} else {
			writeln(`Parsing`, type, " ", path, " FAILED, options: ", options);
		}
	}

	private double bytesPer(T)(in T num, in Duration dur) => (cast(typeof(return))num) / dur.total!("nsecs")() * 1e9;
}

alias JSONDocument = Document!(const(char), false);
alias JSONDocumentMMap = Document!(const(char), true);

/++ Parse JSON Document from `data`.
 +  See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Result!(Document!(const(char), false), ReadError) parseJSONDocument(Char = const(char))(return scope const(char)[] data, in Options options = Options.none) pure nothrow @nogc @trusted {
	ReadError err;
    auto doc = yyjson_read_opts(data.ptr, data.length, options._flag, null, cast(yyjson_read_err*)&err/+same layout+/);
	return (err.code == ReadCode.SUCCESS ? typeof(return)(Document!(Char, false)(doc, data)) : typeof(return)(err));
}

/++ Parse JSON Document from `mmfile`.
 +  See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Result!(JSONDocumentMMap, ReadError) parseJSONDocumentMmap(Char = const(char))(return scope MmFile mmfile, in Options options = Options.none) /+pure nothrow @nogc+/ @trusted {
	ReadError err;
	const data = (cast(const(char)[])mmfile[]);
    auto doc = yyjson_read_opts(data.ptr, data.length, options._flag, null, cast(yyjson_read_err*)&err/+same layout+/);
	return (err.code == ReadCode.SUCCESS ? typeof(return)(Document!(Char, true)(doc, mmfile)) : typeof(return)(err));
}

/// Read document from empty string.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = ``;
	scope const docR = s.parseJSONDocument();
	assert(!docR);
}

/// Test none.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const scope root = Value();
	assert(root.type == ValueType.NONE);
	assert(root.type_std == JSONType.none);
	assert(root.isNone);
}

/// Equality value.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `null`;
	scope const docR = s.parseJSONDocument();
	assert(docR == docR);
}

/// Read null value.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `null`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).data.length == s.length);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	const scope root = (*docR).root;
	assert(root.type == ValueType.NULL);
	assert(root.type_std == JSONType.null_);
	assert(root.isNull);
}

/// Read boolean numbers.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	foreach (const e; [false, true]) {
		const s = e ? `true` : `false`;
		scope docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		const scope root = (*docR).root;
		assert(root);
		assert(root.boolean == e);
		if (e)
			assert(root.isTrue);
		else
			assert(root.isFalse);
	}
}

/// Read negative signed integer (`integer`).
@safe pure nothrow /+@nogc+/ version(yyjson_test) unittest {
	foreach (const e; -100 .. -1) {
		const s = e.to!string;
		scope docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		const scope root = (*docR).root;
		assert(root.integer == e);
	}
}

/// Read positive unsigned integer (`uinteger`)
@safe pure nothrow /+@nogc+/ version(yyjson_test) unittest {
	foreach (const e; 0 .. 100) {
		const s = e.to!string;
		scope docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		const scope root = (*docR).root;
		assert(root.uinteger == e);
	}
}

/// Read floating-point (real) number (`floating`).
@safe pure /+@nogc+/ version(yyjson_test) unittest {
	const s = `0.5`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	const scope root = (*docR).root;
	assert(root.floating == 0.5);
}

/// Read string.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `"alpha"`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	const scope root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.STR);
	assert(root.isString);
	assert(root.type_std == JSONType.string);
	assert(root.str == "alpha");
}

/// Read array and iterate its range
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3]`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
	assert(root.isArray);
	assert(root.isFlatArray);
	assert(root.arrayLength == 3);
	size_t ix = 0;
	assert(root.arrayRange.length == 3);
	foreach (const ref e; root.arrayRange()) {
		assert(e.type == ValueType.NUM);
		ix += 1;
	}
	assert(ix == 3);
}

/// Read object and index using string key
@safe pure version(yyjson_test) unittest {
	enum n = 3;

	const string[n] keys = ["a", "a", "b"]; // duplicate keys allowed
	const uint[n] vals = [1, 1, 2];

	const s = `{"a":1, "a":1, "b":2}`; // duplicate keys allowed
	scope docR = s.parseJSONDocument();

	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 7);

	const Value root = (*docR).root;

	assert(root.object["a"]);
	assert(root.object["b"]);

	bool thrown = false;
	try {
		auto _ = root.object["c"];
	} catch (Exception _)
		thrown = true;
	assert(thrown);
}

/// Read object and iterate its range
@safe pure nothrow @nogc version(yyjson_test) unittest {
	enum n = 3;

	const string[n] keys = ["a", "a", "b"]; // duplicate keys allowed
	const uint[n] vals = [1, 1, 2];

	const s = `{"a":1, "a":1, "b":2}`; // duplicate keys allowed
	scope docR = s.parseJSONDocument();

	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 7);

	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.OBJ);
	assert(root.type_std == JSONType.object);
	assert(root.objectLength == n);

	assert(root.objectRange.find("a"));
	assert(root.objectRange.find("b"));
	assert(!root.objectRange.find("c"));
	assert(root.objectRange.length == n);

	size_t ix = 0;
	foreach (const ref kv; root.objectRange()) {
		assert(kv.key.type == ValueType.STR);
		assert(kv.key.type_std == JSONType.string);
		assert(kv.value.type == ValueType.NUM);
		assert(kv.key.str == keys[ix]);
		assert(kv.value.uinteger == vals[ix]);
		ix += 1;
	}
	assert(ix == n);
}

/// Read array and iterate its GC-allocated slice.
@safe pure nothrow version(yyjson_test) unittest {
	const s = `[1,2,3]`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
	assert(root.arrayLength == 3);
	{
		size_t ix = 0;
		foreach (const ref e; root.arraySlice()) {
			assert(e.type == ValueType.NUM);
			ix += 1;
		}
		assert(ix == 3);
	}
}

/// Read integer.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `1`;
	scope docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	const scope root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.NUM);
	// assert(root.floating == 1.0);
}

/// Read array with trailing comma and comment.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3,] // a comment`;
	scope docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_COMMENTS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	const scope root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
}

/// Read object with trailing commas.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `{"a":11, "b":{"x":3.14, "y":42}, "c":[1,2,3,],}`;
	scope docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 14);
	const scope root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.OBJ);
	assert(root.isObject);
	assert(root.type_std == JSONType.object);
	const a_val = "a" in root;
	assert(a_val.uinteger == 11);
	assert(root["a"].uinteger == 11);
	const x_val = "x" in root;
	assert(!x_val);
	assert(root["x"].isNone);
}

/// Read string with slash to verify that slashes are not escaped by default opposite to D's `std.json`.
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `"/"`;
	scope docR = s.parseJSONDocument();
	assert(docR);
	const scope root = (*docR).root;
	assert(root.type == ValueType.STR);
}

/++ Path. +/
struct Path {
	this(string str, in bool normalize = false) pure nothrow @nogc {
		this.str = str;
	}
	string str;
pure nothrow @nogc:
	bool opCast(T : bool)() const scope => str !is null;
	string toString() const @property => str;
}

/++ (Regular) file path (on local file system). +/
struct FilePath {
	this(string str, in bool normalize = false) pure nothrow @nogc {
		this.path = Path(str, normalize);
	}
	Path path;
	alias path this;
}

/++ Directory path (on local file system). +/
struct DirPath {
	this(string path, in bool normalize = false) pure nothrow @nogc {
		this.path = Path(path, normalize);
	}
	Path path;
	alias path this;
}
/++ Get path to home directory.
 +	See_Also: `tempDir`
 +  See: https://forum.dlang.org/post/gg9kds$1at0$1@digitalmars.com
 +/
private DirPath homeDir() {
	import std.process : environment;
    version(Windows) {
        // On Windows, USERPROFILE is typically used, but HOMEPATH is an alternative
		if (const home = environment.get("USERPROFILE"))
			return typeof(return)(home);
        // Fallback to HOMEDRIVE + HOMEPATH
        const homeDrive = environment.get("HOMEDRIVE");
        const homePath = environment.get("HOMEPATH");
        if (homeDrive && homePath)
            return typeof(return)(buildPath(homeDrive, homePath));
    } else {
        if (const home = environment.get("HOME"))
			return typeof(return)(home);
    }
    throw new Exception("No home directory environment variable is set.");
}

version (yyjson_dub_benchmark) {
import std.file : dirEntries, SpanMode;
import std.path : buildPath, baseName, expandTilde;
import std.mmfile : MmFile;
debug import std.stdio : writeln;

@safe version(yyjson_test) unittest {
	const path = homeDir.str.buildPath("5MB-min.json");
	() @trusted {
		scope mmfile = new MmFile(path);
		const src = (cast(const(char)[])mmfile[]);
		auto sw = StopWatch(AutoStart.yes);
		const doc = src.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
		debug const dur = sw.peek;
		const mbps = src.length.bytesPer(dur) * 1e-6;
		if (doc) {
 			debug writeln(`Parsing `, path, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to SUCCEED");
		} else {
			debug writeln(`Parsing `, path, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to FAIL");
		}
	}();
}

version(none)
@safe version(yyjson_test) unittest {
	const root = homeDir.str.buildPath(".dub/packages.all");
	foreach (ref dent; dirEntries(root, SpanMode.depth)) {
		if (dent.isDir)
			continue;
		if (dent.baseName == "dub.json")
			() @trusted {
				scope mmfile = new MmFile(dent.name);
				// debug writeln("Parsing ", dent.name, " ...");
				const src = (cast(const(char)[])mmfile[]);
				auto sw = StopWatch(AutoStart.yes);
				const doc = src.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
				debug const dur = sw.peek;
				const mbps = src.length.bytesPer(dur) * 1e-6;
				if (doc) {
 					// debug writeln(`Parsing `, dent.name, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to SUCCEED");
				} else {
					debug writeln(`Parsing `, dent.name, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to FAIL");
				}
			}();
	}
}

}

version(yyjson_test) version(unittest) {
	import std.conv : to;
}

import yyjson_c; // ImportC yyjson.c. Functions are overrided below.
// Need these because ImportC doesn't support overriding qualifiers.
extern(C) private pure nothrow @nogc {
import core.stdc.stdint : uint32_t, uint64_t, int64_t;
yyjson_doc *yyjson_read_opts(scope const(char)* dat,
                             size_t len,
                             yyjson_read_flag flg,
                             const yyjson_alc *alc,
                             yyjson_read_err *err);
alias MallocFn = void* function(void* ctx, size_t size);
alias ReallocFn = void* function(void* ctx, void* ptr, size_t old_size, size_t size);
alias FreeFn = void function(void* ctx, void* ptr);
// struct yyjson_alc {
// pure nothrow @nogc:
//     /** Same as libc's malloc(size), should not be NULL. */
// 	MallocFn malloc;
//     /** Same as libc's realloc(ptr, size), should not be NULL. */
// 	ReallocFn realloc;
//     /** Same as libc's free(ptr), should not be NULL. */
// 	FreeFn free;
//     /** A context for malloc/realloc/free, can be NULL. */
//     void *ctx;
// }

// value:
bool unsafe_yyjson_get_bool(const yyjson_val* _val);

// array:
size_t yyjson_arr_size(const yyjson_val *arr);
const(yyjson_val) *yyjson_arr_get(const(yyjson_val) *arr, size_t idx);
// array iterator:
bool yyjson_arr_iter_init(const yyjson_val *arr, yyjson_arr_iter *iter);
bool yyjson_arr_iter_has_next(yyjson_arr_iter *iter);
yyjson_val *yyjson_arr_iter_next(yyjson_arr_iter *iter);
// array predicate:
bool unsafe_yyjson_arr_is_flat(const yyjson_val *val);

// object:
size_t yyjson_obj_size(const yyjson_val *obj);
// object iterator:
bool yyjson_obj_iter_init(const yyjson_val *obj, yyjson_obj_iter *iter);
bool yyjson_obj_iter_has_next(yyjson_obj_iter *iter);
yyjson_val *yyjson_obj_iter_next(yyjson_obj_iter *iter);
yyjson_val *yyjson_obj_iter_get_val(yyjson_val *key);
yyjson_val *yyjson_obj_getn(yyjson_val *obj, const char *key, size_t key_len);
}

void dbg(Args...)(scope auto ref Args args, in string file = __FILE_FULL_PATH__, in uint line = __LINE__) pure nothrow {
	import core.stdc.stdio : stdout, stderr, fflush;
	import std.stdio : write;
	debug {
		() @trusted {
		write(file);
		write("(");
		write(line);
		write("): Debug: ");
		writeln(args);
		stderr.fflush(); // before a potentially crash happens
	}();
	}
}
