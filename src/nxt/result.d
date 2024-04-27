/++ Result type.
 +/
module nxt.result;

@safe:

/++ Result of `T` with optional error `E`.
	Designed for error handling where an operation can either succeed or fail.
	- TODO: Add member `toRange` alias with `opSlice`
	- TODO: Add member visit()
 +/
struct Result(T, E = void) {
	static if (!__traits(isPOD, T))
		import core.lifetime : move, moveEmplace;
	this(T value) {
		static if (__traits(isPOD, T))
			_value = value;
		else
			() @trusted { moveEmplace(value, _value); }(); /+ TODO: remove when compiler does this +/
		_isValid = true;
	}
	static if (!is(E == void)) {
		this(E error) {
			static if (__traits(isPOD, T))
				_error = error;
			else
				() @trusted { moveEmplace(error, _error); }(); /+ TODO: remove when compiler does this +/
			_isValid = false;
		}
	}
	~this() @trusted {
		import core.internal.traits : hasElaborateDestructor;
		if (hasValue) {
			static if (hasElaborateDestructor!T)
				.destroy(_value);
		} else {
			static if (hasElaborateDestructor!E)
				.destroy(_error);
		}
	}
	ref typeof(this) opAssign(T value) @trusted {
		static if (__traits(isPOD, T))
			_value = value;
		else
			() @trusted { move(value, _value); }(); /+ TODO: remove when compiler does this +/
		_isValid = true;
		return this;
	}
@property:
	ref inout(T) value() inout scope @trusted return in(isValid) => _value;
	static if (!is(E == void)) {
		ref inout(E) error() inout scope @trusted return in(!isValid) => _error;
	}
	// ditto
	ref inout(T) opUnary(string op)() inout scope return if (op == "*") => value;
	bool opEquals(in T that) const scope => _isValid ? value == that : false;
	bool opEquals(scope const ref T that) const scope => _isValid ? value == that : false;
	bool opEquals(scope const ref typeof(this) that) const scope @trusted {
		if (this.isValid && that.isValid)
			return this._value == that._value;
		return this.isValid == that.isValid;
	}
	string toString() inout scope pure @trusted {
		import std.conv : to;
		return isValid ? _value.to!string : "invalid";
	}
pure nothrow @nogc:
	bool isValid() const scope => _isValid;
	alias hasValue = isValid;
	static if (!is(E == void)) {
		bool isError() const scope => !_isValid;
	}
	bool opCast(T : bool)() const scope => _isValid;
	static typeof(this) invalid() => typeof(this).init;
private:
	/++ TODO: avoid `_isValid` when `T` is a pointer and `_error.sizeof` <=
		`size_t.sizeof:` by making some part part of pointer the
		discriminator for a defined value preferrably the lowest bit.
     +/
	static if (!is(E == void)) {
		union {
			T _value;
			E _error;
		}
	} else {
	    T _value;
	}
	bool _isValid;
}

/// to string conversion
@safe pure unittest {
	alias T = int;
	alias R = Result!T;
	const R r1;
	assert(r1.toString == "invalid");
	const R r2 = 42;
	assert(r2.toString == "42");
	R r3 = r2;
	r3 = 42;
	assert(*r3 == 42);
	assert(r3 == 42);
	T v42 = 42;
	assert(r3 == v42);
}

/// result of uncopyable type
@safe pure nothrow @nogc unittest {
	alias T = Uncopyable;
	alias R = Result!T;
	R r1;
	assert(!r1);
	assert(r1 == R.invalid);
	assert(r1 != R(T.init));
	assert(!r1.isValid);
	T t = T(42);
	r1 = move(t);
	assert(r1 != R(T.init));
	assert(*r1 == T(42));
	R r2 = T(43);
	assert(*r2 == T(43));
	assert(r2.value == T(43));
}

/// result of point and error
@safe pure nothrow unittest {
	alias V = ulong;
	alias T = V*;
	enum E { first, second }
	alias R = Result!(T, E);
	R r1;
	assert(!r1);
	assert(r1 == R.invalid);
	assert(r1 != R(T.init));
	assert(!r1.isValid);
	assert(r1.isError);
	assert(r1.error == E.init);
	assert(r1.error == E.first);
	T t = new V(42);
	r1 = move(t);
	assert(r1 != R(T.init));
	assert(**r1 == V(42));
	R r2 = new V(43);
	assert(**r2 == V(43));
	assert(*r2.value == V(43));
}

version (unittest) {
	import core.lifetime : move;
	private static struct Uncopyable { this(this) @disable; int _x; }
}
