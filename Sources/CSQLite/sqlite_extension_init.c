#include "sqlite3ext.h"

SQLITE_EXTENSION_INIT1

void SQLiteExtensionKitInitialize(const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi);
}
