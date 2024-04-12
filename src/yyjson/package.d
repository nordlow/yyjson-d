/** Idiomatic D-style wrapper around yyjson C API mimicing
    https://dlang.org/library/std/json/parse_json.html.
 */
module yyjson;

@safe:

/++ JSON Document.
	TODO: Wrap in `Result` type.
 +/
struct Document {
pure nothrow @nogc:
	@disable this(this);
	~this() @trusted {
		version (none) // TODO: enable
		if (_doc) {
			if (_doc.str_pool)
				_doc.alc.free(_doc.alc.ctx, _doc.str_pool);
			_doc.alc.free(_doc.alc.ctx, _doc);
			_doc.alc = typeof(_doc.alc).init;
		}
	}
	this(yyjson_doc* _doc) in(_doc) { this._doc = _doc; }

// TODO: pragma(inline, true):

	bool opCast(T : bool)() const scope => _doc !is null;

	/++ Returns: root value or `null` if `_doc` is `null`. +/
	const(Value) root() const scope => typeof(return)(_doc ? _doc.root : null);

	/++ Returns: total number of bytes read (nonzero). +/
	size_t byteCount() const scope => _doc.dat_read;

	/++ Returns: total number of (node) values read (nonzero). +/
	size_t valueCount() const scope => _doc.val_read;
private:
	yyjson_doc* _doc;
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

/++ JSON Value.
	TODO: Wrap in `Result` type.
 +/
struct Value {
pure nothrow @nogc:
	@disable this(this);
	bool opCast(T : bool)() const scope => _val !is null;
	ValueType type() const scope => cast(typeof(return))(_val.tag & YYJSON_TYPE_MASK);
	private yyjson_val* _val;
}

struct Options {
	private yyjson_read_flag _flag;
}

/** Error information for JSON reader. */
alias ReadError = yyjson_read_err;

/++ Parse JSON Document from `data`.
    See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Document parseJSON(in char[] data, in Options options) @trusted pure nothrow @nogc {
	ReadError err;
    auto doc = yyjson_read_opts(data.ptr, data.length, options._flag, null, &err);
	assert(err.code == 0, "TODO: return Result failure error using `err` fields");
	return typeof(return)(err.code == 0 ? doc : doc);
}

@safe pure nothrow @nogc unittest {
	const s = `{"a":1, "b":{"x":3.14, "y":42}, "c":[1,2,3]}`;
	auto doc = s.parseJSON(Options.init);
	assert(doc);
	assert(doc.byteCount == s.length);
	assert(doc.valueCount == 14);
	auto root = doc.root;
	assert(root);
	assert(root.type == ValueType.OBJ);
}

import yyjson.yyjson_c; // ImportC yyjson.c. Functions are overrided below.
// Need these because ImportC doesn't support overriding qualifiers.
extern(C) private pure nothrow @nogc {
import core.stdc.stdint : uint32_t, uint64_t, int64_t;
void yyjson_doc_free(yyjson_doc *doc);
yyjson_doc *yyjson_read_opts(scope const(char)* dat,
                             size_t len,
                             yyjson_read_flag flg,
                             const yyjson_alc *alc,
                             yyjson_read_err *err);
struct yyjson_alc {
pure nothrow @nogc:
    /** Same as libc's malloc(size), should not be NULL. */
	void* function(void* ctx, size_t size) malloc;
    /** Same as libc's realloc(ptr, size), should not be NULL. */
	void* function(void* ctx, void* ptr, size_t old_size, size_t size) realloc;
    /** Same as libc's free(ptr), should not be NULL. */
	void function(void* ctx, void* ptr) free;
    /** A context for malloc/realloc/free, can be NULL. */
    void *ctx;
}
}
