/** D-wrapper around `yyjson` mimicing `std.json`.
 */
module yyjson;

import std.mmfile : MmFile;
import yyjson.result : Result;

@safe:

/++ JSON Document.
 +
 +  TODO: Turn into a result type being either a non-null pointer or an error type.
 +  Descriminator can be the least significant bit.
 +
 +  See_Also: https://en.wikipedia.org/wiki/Mmap
 +/
struct Document(Char = const(char), bool memoryMapped = false)
if (is(Char == const char) || is(Char == immutable char)) {
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
	const(Value!(Char)) root() const scope => typeof(return)(_doc ? _doc.root : null);

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

/++ JSON Value (Reference Pointer). +/
struct Value(Char)
if (is(Char == const char) || is(Char == immutable char)) {
	import core.stdc.string : strlen;

	private yyjson_val* _val;

	static if (is(Char == immutable(char))) {
		/***
		 * Implicitly calls `toJSON` on this JSONValue.
		 *
		 * $(I options) can be used to tweak the conversion behavior.
		 */
		.string toString(in JSONOptions options = JSONOptions.none) const
		{
			return toJSON(this, false, options);
		}
		void toString(Out)(Out sink, in Options options = Options.none) const {
			toJSON(sink, this, false, options);
		}
	}

pure nothrow @property:
	this(const(yyjson_val)* val) const scope nothrow @nogc @trusted {
		_val = cast(yyjson_val*)val;
	}

	/// For `std.json` compliance. Allocates with the GC!
	const(Value!(Char))[] arraySlice() const /+return scope+/ in(type == ValueType.ARR) {
		const length = yyjson_arr_size(_val);
		typeof(return) res;
		res.reserve(length);
		foreach (const idx; 0 .. length)
			res ~= const(Value!(Char))(yyjson_arr_get(_val, idx));
		return res;
	}

	/++ TODO: Get value as an array. +/
	version(none)
	auto array() const in(type == ValueType.ARR) {
		import std.array : array;
		return arrayRange.array;
	}

@nogc:

	/++ Get value as a {range|view} over array elements. +/
	auto arrayRange() const in(type == ValueType.ARR) {
		static struct Result {
		private:
			yyjson_arr_iter _iter;
			const(yyjson_val)* _val;
			size_t _length;
		scope pure nothrow @safe @nogc:
		/+pragma(inline, true):+/
			// @disable this(this);
			this(const(yyjson_val)* arr) @trusted {
				_length = yyjson_arr_size(arr);
				const _ = yyjson_arr_iter_init(cast()arr, &_iter);
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
			const(Value!(Char)) front() return scope in(!empty) => typeof(return)(_val);
		}
		return Result(_val);
 	}
	alias array = arrayRange; // `std.traits` compliance

	/++ Object key type. +/
	alias Key = Value;

	/++ Object value type. +/
	alias Value = .Value;

	/++ Check if element with key `key` is stored/contained. +/
	const(Value!(Char)) opBinaryRight(.string op)(in char[] key) const return scope @trusted if (op == "in") {
		return typeof(return)(yyjson_obj_getn(cast(yyjson_val*)_val, key.ptr, key.length));
	}

	/++ Get element value with key `key`. +/
	const(Value!(Char)) opIndex(in char[] key) const return scope @trusted {
		return typeof(return)(yyjson_obj_getn(cast(yyjson_val*)_val, key.ptr, key.length));
	}

	/++ TODO: Get value as an object. +/

	/++ Get value as a {range|view} over object elements (key-values). +/
	auto objectRange() const in(type == ValueType.OBJ) {
		/++ Object key-value (element) type. +/
		struct KeyValue {
			Key!(Char) key; ///< Key part of object element.
			Value!(Char) value; ///< Value part of object element.
		}
		static struct Result {
		private:
			yyjson_obj_iter _iter;
			const(yyjson_val)* _key;
			size_t _length;
		/+pragma(inline, true):+/
		scope pure @safe:
			public const(Value!(Char)) opIndex(in char[] key) @property return scope {
				auto hit = find(key);
				if (!hit)
					throw new Exception(("Key " ~ key ~ " not found").idup);
				return hit;
			}
		nothrow @nogc:
			// @disable this(this);
			this(const(yyjson_val)* obj) @trusted {
				_length = yyjson_obj_size(obj);
				const _ = yyjson_obj_iter_init(cast()obj, &_iter);
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
			const(Value!(Char)) find(in char[] key) return scope {
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
			const(Key!(Char)) frontKey() return scope in(!empty) => typeof(return)(_key);
			const(Value!(Char)) frontValue() return scope @trusted in(!empty) {
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

	/++ Value getters. TODO: These should return result types or throw +/

	/++ Get value as a boolean. +/
	bool boolean() @trusted in(type == ValueType.BOOL) => unsafe_yyjson_get_bool(cast(yyjson_val*)_val);

	/++ Get value as a signed integer number. +/
	long integer() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_SINT)) => _val.uni.i64;

	/++ Get value as an unsigned integer number. +/
	ulong uinteger() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_UINT)) => _val.uni.u64;

	/++ Get value as a floating point number. +/
	double floating() in(_val.tag == (YYJSON_TYPE_NUM | YYJSON_SUBTYPE_REAL)) => _val.uni.f64;

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
	bool isNone() => _val is null;

	/++ Returns: `true` iff `this` has value `null`. +/
	bool isNull() => (_val.tag == (YYJSON_TYPE_NULL)) != 0;

	/++ Returns: `true` iff `this` has value `false`. +/
	bool isFalse() => (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_FALSE));

	/++ Returns: `true` iff `this` has value `true`. +/
	bool isTrue() => (_val.tag == (YYJSON_TYPE_BOOL | YYJSON_SUBTYPE_TRUE));

	/++ Returns: `true` iff `this` is a boolean. +/
	bool isBoolean() => type == ValueType.BOOL;

	/++ Returns: `true` iff `this` is a string. +/
	bool isString() => type == ValueType.STR;

	/++ Returns: `true` iff `this` is an array. +/
	bool isArray() => type == ValueType.ARR;

	/++ Returns: `true` iff `this` is a flat array. +/
	bool isFlatArray() @trusted => isArray && unsafe_yyjson_arr_is_flat(_val);

	/++ Returns: `true` iff `this` is an object. +/
	bool isObject() => type == ValueType.OBJ;
}
/// ditto
alias JSONValue = Value!(immutable(char)); // `std.json` compliance

/**
Takes a tree of JSON values and returns the serialized string.

Any Object types will be serialized in a key-sorted order.

If `pretty` is false no whitespaces are generated.
If `pretty` is true serialized string is formatted to be human-readable.
Set the $(LREF JSONOptions.specialFloatLiterals) flag is set in `options` to encode NaN/Infinity as strings.
*/
string toJSON(const ref JSONValue root, in bool pretty = false, in JSONOptions options = JSONOptions.none) @safe
{
	import std.array : Appender;
    Appender!(string) json;
    toJSON(json, root, pretty, options);
    return json.data;
}

import std.range.primitives : isOutputRange;

///
void toJSON(Out)(
    auto ref Out json,
    const ref JSONValue root,
    in bool pretty = false,
    in JSONOptions options = JSONOptions.none)
if (isOutputRange!(Out,char))
{
    void toStringImpl(Char)(string str)
    {
        json.put('"');

        foreach (Char c; str)
        {
            switch (c)
            {
                case '"':       json.put("\\\"");       break;
                case '\\':      json.put("\\\\");       break;

                case '/':
                    if (!(options._doNotEscapeSlashes))
                        json.put('\\');
                    json.put('/');
                    break;

                case '\b':      json.put("\\b");        break;
                case '\f':      json.put("\\f");        break;
                case '\n':      json.put("\\n");        break;
                case '\r':      json.put("\\r");        break;
                case '\t':      json.put("\\t");        break;
                default:
                {
                    import std.ascii : isControl;
                    import std.utf : encode;

                    // Make sure we do UTF decoding iff we want to
                    // escape Unicode characters.
                    assert(((options._escapeNonAsciiChars) != 0)
                        == is(Char == dchar), "JSONOptions.escapeNonAsciiChars needs dchar strings");

                    with (JSONOptions) if (isControl(c) ||
                        ((options._escapeNonAsciiChars) && c >= 0x80))
                    {
                        // Ensure non-BMP characters are encoded as a pair
                        // of UTF-16 surrogate characters, as per RFC 4627.
                        wchar[2] wchars; // 1 or 2 UTF-16 code units
                        size_t wNum = encode(wchars, c); // number of UTF-16 code units
                        foreach (wc; wchars[0 .. wNum])
                        {
                            json.put("\\u");
                            foreach_reverse (i; 0 .. 4)
                            {
                                char ch = (wc >>> (4 * i)) & 0x0f;
                                ch += ch < 10 ? '0' : 'A' - 10;
                                json.put(ch);
                            }
                        }
                    }
                    else
                    {
                        json.put(c);
                    }
                }
            }
        }

        json.put('"');
    }

    void toString(string str)
    {
        // Avoid UTF decoding when possible, as it is unnecessary when
        // processing JSON.
        if (options._escapeNonAsciiChars)
            toStringImpl!dchar(str);
        else
            toStringImpl!char(str);
    }

    /* make the function infer @system when json.put() is @system
     */
    if (0)
        json.put(' ');

    /* Mark as @trusted because json.put() may be @system. This has difficulty
     * inferring @safe because it is recursive.
     */
    void toValueImpl(ref const JSONValue value, ulong indentLevel) @trusted {
        void putTabs(ulong additionalIndent = 0) {
            if (pretty)
                foreach (i; 0 .. indentLevel + additionalIndent)
                    json.put("    ");
        }
        void putEOL() {
            if (pretty)
                json.put('\n');
        }
        void putCharAndEOL(char ch) {
            json.put(ch);
            putEOL();
        }

        final switch (value.type) {
        case JSONType.object:
            auto obj = value.objectRange;
            if (!obj.length) {
                json.put("{}");
            } else {
                putCharAndEOL('{');
                bool first = true;

                foreach (const ref pair; obj) {
					if (!first)
						putCharAndEOL(',');
					first = false;
					putTabs(1);
					json.put(pair.key.str);
					json.put(':');
					if (pretty)
						json.put(' ');
					toValueImpl(pair.value, indentLevel + 1);
				}

                putEOL();
                putTabs();
                json.put('}');
            }
			break;

        case JSONType.array:

            auto obj = value.arrayRange;
            if (!obj.length) {
                json.put("[]");
            } else {
                putCharAndEOL('[');
                bool first = true;

				import core.lifetime : move;
                foreach (const ref elm; move(obj)) {
					if (!first)
						putCharAndEOL(',');
					first = false;
					putTabs(1);
					toValueImpl(elm, indentLevel + 1);
				}

                putEOL();
                putTabs();
                json.put(']');
            }
			break;

        case JSONType.string:
            json.put(value.str);
            break;

        case JSONType.integer:
            json.put(to!string(value.integer));
            break;

        case JSONType.uinteger:
            json.put(to!string(value.uinteger));
            break;

        case JSONType.float_:
            import std.math.traits : isNaN, isInfinity;
            auto val = value.floating;
            if (val.isNaN) {
                if (options._specialFloatLiterals) {
					json.put("nan");
                } else {
                    throw new Exception(
										"Cannot encode NaN. Consider passing the specialFloatLiterals flag.");
                }
            } else if (val.isInfinity) {
                if (options._specialFloatLiterals) {
					json.put((val > 0) ?  "inf" : "-inf");
                } else {
                    throw new Exception(
										"Cannot encode Infinity. Consider passing the specialFloatLiterals flag.");
                }
            } else {
                import std.algorithm.searching : canFind;
                import std.format : sformat;
                // The correct formula for the number of decimal digits needed for lossless round
                // trips is actually:
                //     ceil(log(pow(2.0, double.mant_dig - 1)) / log(10.0) + 1) == (double.dig + 2)
                // Anything less will round off (1 + double.epsilon)
                char[25] buf;
                auto result = buf[].sformat!"%.18g"(val);
                json.put(result);
                if (!result.canFind('e') && !result.canFind('.'))
                    json.put(".0");
            }
            break;

        case JSONType.true_:
            json.put("true");
            break;

        case JSONType.false_:
            json.put("false");
            break;

        case JSONType.null_:
            json.put("null");
            break;
        }
    }

    toValueImpl(root, 0);
}

// https://issues.dlang.org/show_bug.cgi?id=12897
@safe unittest
{
	const doc0 = `"test测试"`.parseJSONDocument();
    const JSONValue jv0 = (*doc0).root;
	assert(jv0.str == "test测试");

	// TODO:
    // assert(toJSON(jv0, false, JSONOptions.escapeNonAsciiChars) == `"test\u6D4B\u8BD5"`);
    // JSONValue jv00 = JSONValue("test\u6D4B\u8BD5");
    // assert(toJSON(jv00, false, JSONOptions.none) == `"test测试"`);
    // assert(toJSON(jv0, false, JSONOptions.none) == `"test测试"`);
    // JSONValue jv1 = JSONValue("été");
    // assert(toJSON(jv1, false, JSONOptions.escapeNonAsciiChars) == `"\u00E9t\u00E9"`);
    // JSONValue jv11 = JSONValue("\u00E9t\u00E9");
    // assert(toJSON(jv11, false, JSONOptions.none) == `"été"`);
    // assert(toJSON(jv1, false, JSONOptions.none) == `"été"`);
}

/// arrays
@safe unittest
{
	const doc0 = `["a"]`.parseJSONDocument();
    const JSONValue jv0 = (*doc0).root;
	assert(jv0.isArray);
	// assert(jv0.toString == `["a"]`);
}

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
	static typeof(this) escapeNonAsciiChars() => typeof(this)(false, true, false);
	static typeof(this) doNotEscapeSlashes() => typeof(this)(false, false, true);

	enum none = typeof(this).init;
	enum allowAll = typeof(this)(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE | ReadFlag.ALLOW_COMMENTS | ReadFlag.ALLOW_INF_AND_NAN, false, true);

	private yyjson_read_flag _flag;
	private bool _escapeNonAsciiChars;
	private bool _doNotEscapeSlashes;
	private bool _specialFloatLiterals;
}
alias JSONOptions = Options; // `std.json` compliance

/++ Parse JSON Document from `path`.
	TODO: Add options for allocation mechanism and immutablity.
 +/
Result!(Document!(Char, memoryMapped), ReadError)
readJSONDocument(Char = const(char), bool memoryMapped = false)(in FilePath path, in Options options = Options.none) /+nothrow @nogc+/ @trusted /+@reads_from_file+/ {
	static if (memoryMapped) {
		return parseJSONDocumentMmap(new MmFile(path.str), options: options);
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
	const fn = FilePath("test-data/metaModel.json");
	const path = FilePath(homeDir.str.buildPath(fn.str));
	if (!path.str.exists)
		return;
	alias Char = const(char);
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, false)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS));
	benchmark!(Char, true)(path, Options(ReadFlag.ALLOW_TRAILING_COMMAS | ReadFlag.ALLOW_INVALID_UNICODE), printElements: true);
}

version(yyjson_benchmark) {
	import std.datetime.stopwatch : StopWatch, AutoStart, Duration;

	private void benchmark(Char = const(char), bool memoryMapped = false)(const FilePath path, Options options = Options.init, bool printElements = false) {
		auto sw = StopWatch(AutoStart.yes);
		const docR = path.readJSONDocument!(Char, memoryMapped)(options);
		const dur = sw.peek;
		if (printElements)
			(*docR).root.convertLSPMetaModelToDCode();
		const mbps = (*docR)._store.length.bytesPer(dur) * 1e-6;
		import std.stdio : writeln;
		const type = memoryMapped ? " memory mapped" : "";
		if (docR) {
 			writeln(`Parsing`, type, " ", path, ` of size `, (*docR)._store.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to SUCCEED, options: ", options);
		} else {
			writeln(`Parsing`, type, " ", path, " FAILED, options: ", options);
		}
	}

	private double bytesPer(in size_t num, in Duration dur) => (cast(typeof(return))num) / dur.total!("nsecs")() * 1e9;

	/++ Convert LSP meta model `mmd` to D code. +/
	string convertLSPMetaModelToDCode(const Value!(const(char)) mmd) {
		typeof(return) res;
		foreach (const section; mmd.objectRange) {
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
}

alias JSONDocument = Document!(const(char), false);
alias JSONDocumentMMap = Document!(const(char), true);

/++ Parse JSON Document from `data`.
 +  See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Result!(Document!(Char, false), ReadError) parseJSONDocument(Char = const(char))(return scope Char[] data, in Options options = Options.none) pure nothrow @nogc @trusted {
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
	const scope root = Value!(immutable(char))();
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
		assert(root.isBoolean);
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
	const root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
	assert(root.isArray);
	assert(root.isFlatArray);
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
	const s = `{"a":1, "a":1, "b":2}`; // duplicate keys allowed
	scope docR = s.parseJSONDocument();

	assert(docR);
	assert((*docR).byteCount == s.length);
	assert((*docR).valueCount == 7);

	const root = (*docR).root;

	assert(root.objectRange["a"]);
	assert(root.objectRange["b"]);

	bool thrown = false;
	try {
		auto _ = root.objectRange["c"];
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

	const root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.OBJ);
	assert(root.type_std == JSONType.object);

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
	const root = (*docR).root;
	assert(root);
	assert(root.type == ValueType.ARR);
	assert(root.type_std == JSONType.array);
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
 					dbg(`Parsing `, dent.name, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to SUCCEED");
				} else {
					dbg(`Parsing `, dent.name, ` of size `, src.length, " at ", cast(size_t)mbps, ` Mb/s took `, dur, " to FAIL");
				}
			}();
	}
}

}

version(yyjson_test) {
	import std.conv : to;
	import yyjson.path;
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
