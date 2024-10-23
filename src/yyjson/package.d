/** D-wrapper around `yyjson` mimicing `std.json`.
 */
module yyjson;

// version = yyjson_dub_benchmark;

import nxt.result : Result;

@safe:

/++ "Immutable" JSON Document.
 +  TODO: Turn into a result type being either a non-null pointer or an error type.
 +  Descriminator can be the least significant bit.
 +/
struct Document {
pure nothrow @nogc:
	@disable this(this);
	~this() @trusted {
		if (!_doc)
			return;
		if (_doc.str_pool)
			(cast(FreeFn)(_doc.alc.free))(_doc.alc.ctx, _doc.str_pool);
		(cast(FreeFn)_doc.alc.free)(_doc.alc.ctx, _doc);
		// uncommented because ASan complains about this: _doc.alc = typeof(_doc.alc).init;
	}
	this(yyjson_doc* _doc) in(_doc) { this._doc = _doc; }

/+pragma(inline, true):+/

	bool opCast(T : bool)() const scope => _doc !is null;

	/++ Returns: root value or `null` if `_doc` is `null`. +/
	const(Value) root() const scope => typeof(return)(_doc ? _doc.root : null);

	/++ Returns: total number of bytes read (nonzero). +/
	size_t byteCount() const scope => _doc.dat_read;

	/++ Returns: total number of (node) values read (nonzero). +/
	size_t valueCount() const scope => _doc.val_read;
	private alias nodeCount = valueCount;

	private yyjson_doc* _doc; // non-null
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

/++ Type of a JSON value being a superset of `std.json.ValueType`.
 + `std.json` compliance.
 +/
enum JSONType : byte
{
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

/++ "Immutable" JSON Value (Reference Pointer). +/
struct Value {
	import core.stdc.string : strlen;

pure nothrow @property:
	/// `std.json` compliance. Allocates with the GC!
	const(Value)[] array() const in(type == ValueType.ARR) {
		const length = yyjson_arr_size(_val);
		typeof(return) res;
		res.reserve(length);
		foreach (const idx; 0 .. length)
			res ~= const(Value)(yyjson_arr_get(_val, idx));
		return res;
	}

@nogc:

	auto arrayRange() const in(type == ValueType.ARR) {
		static struct Result {
		private:
			yyjson_arr_iter _iter;
			yyjson_val* _val;
			size_t _length;
		scope pure nothrow @safe @nogc:
		/+pragma(inline, true):+/
			@disable this(this);
			this(const yyjson_val* arr) @trusted {
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
			size_t length() => _length; // for the sake of `std.traits.hasLength`
			bool empty() => _val is null;
			const(Value) front() return scope in(!empty) => typeof(return)(_val);
		}
		return Result(_val);
 	}

	alias Key = Value;

	struct ObjectKeyValue {
		Key key;
		Value value;
	}

	auto objectRange() const in(type == ValueType.OBJ) {
		static struct Result {
		private:
			yyjson_obj_iter _iter;
			yyjson_val* _key;
			size_t _length;
		scope pure nothrow @safe @nogc:
		/+pragma(inline, true):+/
			@disable this(this);
			this(const yyjson_val* obj) @trusted {
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
			// bool findKey(in char[] key) {
			// 	while (!empty) {
			// 		if () {}
			// 	}
			// }
			// alias tryGetKey = findKey;
		const @property:
			size_t length() => _length; // for the sake of `std.traits.hasLength`
			bool empty() => _key is null;
			Key frontKey() return scope in(!empty) => typeof(return)(_key);
			const(Value) frontValue() return scope @trusted in(!empty) {
				return typeof(return)(yyjson_obj_iter_get_val(cast(yyjson_val*)_key));
			}
			const(ObjectKeyValue) front() return scope => typeof(return)(frontKey, frontValue);
		}
		return Result(_val);
 	}
	alias byKeyValue = objectRange; // `std.traits` compliance

@property const nothrow:
/+pragma(inline, true):+/

	/// Value getters. TODO: These should return result types or throw
	bool boolean() @trusted in(type == ValueType.BOOL) => unsafe_yyjson_get_bool(cast(yyjson_val*)_val);
	long integer() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_SINT)) => _val.uni.i64;
	ulong uinteger() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_UINT)) => _val.uni.u64;
	double floating() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_REAL)) => _val.uni.f64;
	alias float_ = floating;
	const(char)* cstr() @trusted in(type == ValueType.STR) => _val.uni.str;
	const(char)[] str() @trusted => cstr[0..strlen(cstr)];
	private alias string = str;

	size_t arrayLength() in(type == ValueType.ARR) => yyjson_arr_size(_val);
	size_t objectLength() in(type == ValueType.OBJ) => yyjson_obj_size(_val);

nothrow:
	bool opCast(T : bool)() scope => _val !is null;

	ValueType type() scope => cast(typeof(return))(_val.tag & YYJSON_TYPE_MASK);

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

	/// Type predicates:
	bool is_null() => _val.tag == YYJSON_TYPE_NULL;
	alias isNull = is_null;
	bool is_false() => _val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_FALSE);
	alias isFalse = is_false;
	bool is_true() => _val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_TRUE);
	alias isTrue = is_true;

	private yyjson_val* _val;
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
	private yyjson_read_flag _flag;
}
alias JSONOptions = Options; // `std.json` compliance

/++ Parse JSON Document from `data`.
 +  See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Result!(Document, ReadError) parseJSONDocument(in char[] data, in Options options = Options.none) @trusted pure nothrow @nogc {
	ReadError err;
    auto doc = yyjson_read_opts(data.ptr, data.length, options._flag, null, cast(yyjson_read_err*)&err/+same layout+/);
	return (err.code == ReadCode.SUCCESS ? typeof(return)(Document(doc)) : typeof(return)(err));
}

/// Compliance with `std.json.parseJSON`.
Result!(Document, ReadError) parseJSON(in char[] data, int maxDepth = -1, in Options options = Options.none) @trusted pure nothrow @nogc
in(maxDepth == -1, "Setting `maxDepth` is not supported") {
	return data.parseJSONDocument(options);
}

/// empty
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = ``;
	auto docR = s.parseJSONDocument();
	assert(!docR);
}

/// null
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `null`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	auto root = (*docR).root;
	assert(root.is_null);
	assert(root.type == ValueType.NULL);
}

/// boolean
@safe pure nothrow @nogc version(yyjson_test) unittest {
	foreach (const e; [false, true]) {
		const s = e ? `true` : `false`;
		auto docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		auto root = (*docR).root;
		assert(root);
		assert(root.boolean == e);
		if (e)
			assert(root.is_true);
		else
			assert(root.is_false);
	}
}

/// integer
@safe pure nothrow /+@nogc+/ version(yyjson_test) unittest {
	foreach (const e; -100 .. -1) {
		const s = e.to!string;
		auto docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		auto root = (*docR).root;
		assert(root.integer == e);
	}
}

/// uinteger
@safe pure nothrow /+@nogc+/ version(yyjson_test) unittest {
	foreach (const e; 0 .. 100) {
		const s = e.to!string;
		auto docR = s.parseJSONDocument();
		assert(docR);
		assert((*docR).byteCount == s.length);
		assert((*docR).valueCount == 1);
		auto root = (*docR).root;
		assert(root.uinteger == e);
	}
}

/// floating|real
@safe pure /+@nogc+/ version(yyjson_test) unittest {
	const s = `0.5`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	auto root = (*docR).root;
	assert(root.floating == 0.5);
}

/// string
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `"alpha"`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	auto root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.STR);
	assert(root.type_std == JSONType.string);
	assert(root.str == "alpha");
}

/// array range
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3]`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
	assert(root.arrayLength == 3);
	size_t ix = 0;
	assert(root.arrayRange.length == 3);
	foreach (const ref e; root.arrayRange()) {
		assert(e.type == ValueType.NUM);
		ix += 1;
	}
	assert(ix == 3);
}

/// object range
@safe pure nothrow @nogc version(yyjson_test) unittest {
	enum n = 2;
	const string[n] keys = ["a", "b"];
	const uint[n] vals = [1, 2];
	const s = `{"a":1, "b":2}`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 5);
	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.OBJ);
	assert(root.type_std == JSONType.object);
	assert(root.objectLength == n);
	size_t ix = 0;
	assert(root.objectRange.length == n);
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

/// array allocation
@safe pure nothrow version(yyjson_test) unittest {
	const s = `[1,2,3]`;
	auto docR = s.parseJSONDocument();
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
		foreach (const ref e; root.array()) {
			assert(e.type == ValueType.NUM);
			ix += 1;
		}
		assert(ix == 3);
	}
}

/// integers
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `1`;
	auto docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	auto root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.NUM);
	// assert(root.floating == 1.0);
}

/// array with trailing comma and comment
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3,] // a comment`;
	auto docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_COMMENTS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	auto root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
}

/// object with trailing commas
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `{"a":1, "b":{"x":3.14, "y":42}, "c":[1,2,3,],}`;
	auto docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 14);
	auto root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.OBJ);
	assert(root.type_std == JSONType.object);
}

version (yyjson_dub_benchmark) {
import std.datetime.stopwatch : StopWatch, AutoStart, Duration;
@safe version(yyjson_test) unittest {
	import std.file : dirEntries, SpanMode;
	import std.path : buildPath, baseName;
	import std.mmfile : MmFile;
	const root = homeDir.str.buildPath(".dub/packages.all");
	foreach (ref dent; dirEntries(root, SpanMode.depth)) { // TODO: Use overload of dirEntries where depth-span can be set
		if (dent.isDir)
			continue;
		if (dent.baseName == "dub.json")
			() @trusted {
				scope mmfile = new MmFile(dent.name);
				debug import std.stdio : writeln;
				// debug writeln("Parsing ", dent.name, " ...");
				const src = (cast(char[])mmfile[]);
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

private double bytesPer(T)(in T num, in Duration dur)
=> (cast(typeof(return))num) / dur.total!("nsecs")() * 1e9;

private struct Path {
	this(string str) pure nothrow @nogc {
		this.str = str;
	}
	string str;
	pure nothrow @nogc:
	bool opCast(T : bool)() const scope => str !is null;
}

private struct DirPath {
	this(string path) pure nothrow @nogc {
		this.path = Path(path);
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
}

version(unittest) {
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
struct yyjson_alc {
pure nothrow @nogc:
    /** Same as libc's malloc(size), should not be NULL. */
	MallocFn malloc;
    /** Same as libc's realloc(ptr, size), should not be NULL. */
	ReallocFn realloc;
    /** Same as libc's free(ptr), should not be NULL. */
	FreeFn free;
    /** A context for malloc/realloc/free, can be NULL. */
    void *ctx;
}

// value:
bool unsafe_yyjson_get_bool(const yyjson_val* _val);

// array:
size_t yyjson_arr_size(const yyjson_val *arr);
const(yyjson_val) *yyjson_arr_get(const(yyjson_val) *arr, size_t idx);
// array iterator:
bool yyjson_arr_iter_init(const yyjson_val *arr, yyjson_arr_iter *iter);
bool yyjson_arr_iter_has_next(yyjson_arr_iter *iter);
yyjson_val *yyjson_arr_iter_next(yyjson_arr_iter *iter);

// object:
size_t yyjson_obj_size(const yyjson_val *obj);
// object iterator:
bool yyjson_obj_iter_init(const yyjson_val *obj, yyjson_obj_iter *iter);
bool yyjson_obj_iter_has_next(yyjson_obj_iter *iter);
yyjson_val *yyjson_obj_iter_next(yyjson_obj_iter *iter);
yyjson_val *yyjson_obj_iter_get_val(yyjson_val *key);
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
