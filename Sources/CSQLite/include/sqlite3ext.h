/*
** SQLite extension header - minimal wrapper for loadable extensions
** This header provides the necessary declarations for building SQLite extensions
*/

#ifndef SQLITE3EXT_WRAPPER_H
#define SQLITE3EXT_WRAPPER_H

#include <sqlite3.h>

/*
** Make sure we can call this stuff from C++.
*/
#ifdef __cplusplus
extern "C" {
#endif

/*
** These macros are used in the implementation of loadable extensions.
*/
#ifndef SQLITE_EXTENSION_INIT1
#define SQLITE_EXTENSION_INIT1 const sqlite3_api_routines *sqlite3_api = 0;
#endif

#ifndef SQLITE_EXTENSION_INIT2
#define SQLITE_EXTENSION_INIT2(v) sqlite3_api = v;
#endif

#ifndef SQLITE_EXTENSION_INIT3
#define SQLITE_EXTENSION_INIT3(v) \
  SQLITE_EXTENSION_INIT1 \
  SQLITE_EXTENSION_INIT2(v)
#endif

/*
** Helper for Swift to initialize the SQLite API routine table.
*/
void SQLiteExtensionKitInitialize(const sqlite3_api_routines *pApi);

#ifdef __cplusplus
}  /* end of the 'extern "C"' block */
#endif

#endif /* SQLITE3EXT_WRAPPER_H */
