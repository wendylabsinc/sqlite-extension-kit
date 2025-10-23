/*
** SQLite extension header - minimal wrapper for loadable extensions
** This header provides the necessary declarations for building SQLite extensions
*/

#ifndef SQLITE3EXT_WRAPPER_H
#define SQLITE3EXT_WRAPPER_H

#include <sqlite3.h>

#if defined(__has_include_next)
#if __has_include_next(<sqlite3ext.h>)
#ifndef SQLITE_CORE
#define SQLITE_CORE 1
#define SQLITE_EXTENSION_KIT_DEFINED_SQLITE_CORE 1
#endif
#include_next <sqlite3ext.h>
#if defined(SQLITE_EXTENSION_KIT_DEFINED_SQLITE_CORE)
#undef SQLITE_CORE
#undef SQLITE_EXTENSION_KIT_DEFINED_SQLITE_CORE
#endif
#endif
#endif

#ifndef SQLITE3_API_ROUTINES_TYPE_DEFINED
#define SQLITE3_API_ROUTINES_TYPE_DEFINED
typedef struct sqlite3_api_routines sqlite3_api_routines;
#endif

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
int SQLiteExtensionKitIsInitialized(void);

#ifdef __cplusplus
}  /* end of the 'extern "C"' block */
#endif

#endif /* SQLITE3EXT_WRAPPER_H */
