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
	this(yyjson_doc* doc) in(doc) { this._doc = doc; }
	~this() {
		// TODO: yyjson_doc_free(_doc);
	}
    // TODO: pragma(inline, true):
	bool opCast(T : bool)() const scope => _doc !is null;
	inout(Value) root() inout scope => typeof(return)(_doc ? _doc.root : null);
	/++ The total number of bytes read when parsing JSON (nonzero). +/
	size_t bytesRead() const scope => _doc.dat_read;
private:
	yyjson_doc* _doc;
}

/++ JSON Value.
	TODO: Wrap in `Result` type.
 +/
struct Value {
pure nothrow @nogc:
	@disable this(this);
	bool opCast(T : bool)() const scope => _val !is null;
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
	const s = `{"a:":1, "b":2}`;
	auto doc = s.parseJSON(Options.init);
	assert(doc);
	assert(doc.bytesRead == s.length);
	auto root = doc.root;
	assert(root);
}

// import yyjson_c; // ImportC yyjson.c. Functions are overrided below.
// Need these because ImportC doesn't support overriding qualifiers.
extern(C) private pure nothrow @nogc {
import core.stdc.stdint : uint32_t, uint64_t, int64_t;

/** Payload of a JSON value (8 bytes). */
union yyjson_val_uni {
    uint64_t    u64;
    int64_t     i64;
    double      f64;
    const char *str;
    void       *ptr;
    size_t      ofs;
}

/**
 Immutable JSON value, 16 bytes.
 */
struct yyjson_val {
    uint64_t tag; /**< type, subtype and length */
    yyjson_val_uni uni; /**< payload */
}

struct yyjson_alc {
    /** Same as libc's malloc(size), should not be NULL. */
	void* function(void* ctx, size_t size) malloc;
    /** Same as libc's realloc(ptr, size), should not be NULL. */
	void* function(void* ctx, void* ptr, size_t old_size, size_t size) realloc;
    /** Same as libc's free(ptr), should not be NULL. */
	extern (C) void function(void* ctx, void* ptr) free;
    /** A context for malloc/realloc/free, can be NULL. */
    void *ctx;
}

struct yyjson_doc {
    /** Root value of the document (nonnull). */
    yyjson_val *root;
    /** Allocator used by document (nonnull). */
    yyjson_alc alc;
    /** The total number of bytes read when parsing JSON (nonzero). */
    size_t dat_read;
    /** The total number of value read when parsing JSON (nonzero). */
    size_t val_read;
    /** The string pool used by JSON values (nullable). */
    char *str_pool;
}

alias yyjson_read_flag = uint32_t;
alias yyjson_read_code = uint32_t;
struct yyjson_read_err {
    /** Error code, see `yyjson_read_code` for all possible values. */
    yyjson_read_code code;
    /** Error message, constant, no need to free (NULL if success). */
    const char *msg;
    /** Error byte position for input data (0 if success). */
    size_t pos;
}
yyjson_doc *yyjson_read_opts(scope const(char)* dat,
                             size_t len,
                             yyjson_read_flag flg,
                             const yyjson_alc *alc,
                             yyjson_read_err *err);
}
