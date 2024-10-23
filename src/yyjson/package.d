/** D-wrapper around `yyjson` mimicing `std.json`.
 */
module yyjson;

// version = yyjson_dub_benchmark;

debug import std.stdio : writeln;
import std.datetime.stopwatch : StopWatch, AutoStart, Duration;
import nxt.result : Result;

@safe:

/++ Immutable JSON Document.
	TODO: Turn into a result type being either a non-null pointer or an error type.
	Descriminator can be least significant bit.
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

pragma(inline, true):

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

/++ Immutable JSON Value (Reference Pointer). +/
struct Value {
	import core.stdc.string : strlen;
pure nothrow @nogc:
	auto arrayRange() const in(type == ValueType.ARR) {
		struct Result {
		pure nothrow @safe @nogc:
			@disable this(this);
			private this(const yyjson_val* arr) @trusted {
				yyjson_arr_iter_init(cast()arr, &_iter);
				// TODO: Functionize with `Value.popFront`:
				if (yyjson_arr_iter_has_next(&_iter))
					_val = yyjson_arr_iter_next(&_iter);
			}
			bool empty() scope const @trusted => _val is null;
			const(Value) front() return scope in(!empty) => typeof(return)(_val);
			auto popFront() @trusted in(!empty) {
				if (yyjson_arr_iter_has_next(&_iter))
					_val = yyjson_arr_iter_next(&_iter);
				else
					_val = null;
			}
		private:
			yyjson_arr_iter _iter;
			yyjson_val* _val;
		}
		return Result(this._val);
 	}

	auto objectRange() const in(type == ValueType.OBJ) {
		struct Result {
		pure nothrow @nogc:
			@disable this(this);
			private this(const yyjson_val* val) @trusted {
				yyjson_obj_iter_init(cast()val, _iter);
			}
			private yyjson_obj_iter *_iter;
		}
		return Result(this._val);
	}

// pragma(inline, true):

	bool opCast(T : bool)() const scope => _val !is null;

	ValueType type() const scope => cast(typeof(return))(_val.tag & YYJSON_TYPE_MASK);

@property const nothrow:

	bool is_null() => cast(typeof(return)) (_val.tag == YYJSON_TYPE_NULL);
	bool is_false() => cast(typeof(return)) (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_FALSE));
	bool is_true() => cast(typeof(return)) (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_TRUE));
	bool boolean() @trusted in(type == ValueType.BOOL) => unsafe_yyjson_get_bool(cast(yyjson_val*)_val);
	long integer() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_SINT)) => _val.uni.i64;
	ulong uinteger() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_UINT)) => _val.uni.u64;
	double floating() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_REAL)) => _val.uni.f64;
	const(char)* cstr() @trusted in(type == ValueType.STR) => _val.uni.str;
	const(char)[] str() @trusted => cstr[0..strlen(cstr)];
	private alias string = str;

	private yyjson_val* _val;
}
alias JSONValue = Value; // `std.json` compliance

/++ Read flag.
	See: `yyjson_read_flag` in yyjson.h.
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
	See: `yyjson_read_code` in yyjson.h.
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
	Same memory layout as `yyjson_read_err`.
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
    See_Also: https://dlang.org/library/std/json/parse_json.html
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

/// null
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `null`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 1);
	auto root = (*docR).root;
	assert(root.is_null);
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
	assert(root.str == "alpha");
}

/// array
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3]`;
	auto docR = s.parseJSONDocument();
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	const Value root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	size_t count = 0;
	foreach (const ref e; root.arrayRange()) {
		assert(e.type == ValueType.NUM);
		count += 1;
	}
	assert(count == 3);
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

/// array with trailing comma
@safe pure nothrow @nogc version(yyjson_test) unittest {
	const s = `[1,2,3,]`;
	auto docR = s.parseJSONDocument(Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 4);
	auto root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
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
}

version (yyjson_dub_benchmark) {
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
				import std.stdio : writeln;
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
	See_Also: `tempDir`
	See: https://forum.dlang.org/post/gg9kds$1at0$1@digitalmars.com
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

// array iterator:
bool yyjson_arr_iter_init(const yyjson_val *arr,
                          yyjson_arr_iter *iter);
bool yyjson_arr_iter_has_next(yyjson_arr_iter *iter);
yyjson_val *yyjson_arr_iter_next(yyjson_arr_iter *iter);

// object iterator:
bool yyjson_obj_iter_init(const yyjson_val *obj, yyjson_obj_iter *iter);
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
