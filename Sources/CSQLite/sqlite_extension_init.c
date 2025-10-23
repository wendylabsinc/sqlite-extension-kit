#include "sqlite3ext.h"
#include <stddef.h>

SQLITE_EXTENSION_INIT1

static int gSQLiteExtensionKitInitialized = 0;

void SQLiteExtensionKitInitialize(const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi);
    gSQLiteExtensionKitInitialized = pApi != NULL;
}

int SQLiteExtensionKitIsInitialized(void) {
    return gSQLiteExtensionKitInitialized;
}
