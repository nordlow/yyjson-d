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
	bool opCast(T : bool)() const scope => _doc !is null;
	yyjson_doc* _doc;
}

struct Options {
	yyjson_read_flag _flag;
}

/** Error information for JSON reader. */
alias ReadError = yyjson_read_err;

/++ Parse JSON Document from `data`.
    See_Also: https://dlang.org/library/std/json/parse_json.html
 +/
Document parseJSON(in char[] data, in Options options) @trusted pure nothrow @nogc {
	ReadError err;
    return typeof(return)(yyjson_read_opts(data.ptr, data.length, options._flag, null, &err));
}

@safe pure nothrow @nogc unittest {
	const s = `{"a:":1, "b":2}`;
	auto doc = s.parseJSON(Options.init);
	assert(doc);
}

//import yyjson_c; // ImportC yyjson.c. Functions are overrided below.
// Need these because ImportC doesn't support overriding qualifiers.


// Copied from BLAKE3/c/blake3.h
extern(C) private pure nothrow @nogc {
import core.stdc.stdint : uint32_t;

struct yyjson_doc;
struct yyjson_alc;

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
