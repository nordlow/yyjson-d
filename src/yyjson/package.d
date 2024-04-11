/** Idiomatic D-style wrapper around yyjson C API.
 */
module yyjson;

@safe:

import yyjson; // ImportC yyjson.c. Functions are overrided below.
// Need these because ImportC doesn't support overriding qualifiers.
