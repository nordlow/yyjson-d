module yyjson.path;

@safe:

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
DirPath homeDir() {
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
