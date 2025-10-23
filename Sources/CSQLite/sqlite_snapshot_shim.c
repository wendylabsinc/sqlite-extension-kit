#include "sqlite3ext.h"
#include <stddef.h>

#ifndef SQLITE_ENABLE_SNAPSHOT

// Provide stub implementations of the snapshot APIs so that GRDB can link
// against system SQLite builds that were compiled without SQLITE_ENABLE_SNAPSHOT.
// The stubs return SQLITE_ERROR and never hand out snapshot handles.

typedef struct sqlite3_snapshot sqlite3_snapshot;

int sqlite3_snapshot_open(sqlite3 *db, const char *zSchema, sqlite3_snapshot *pSnapshot) {
    (void)db;
    (void)zSchema;
    (void)pSnapshot;
    return SQLITE_ERROR;
}

int sqlite3_snapshot_get(sqlite3 *db, const char *zSchema, sqlite3_snapshot **ppSnapshot) {
    (void)db;
    (void)zSchema;
    if (ppSnapshot) {
        *ppSnapshot = NULL;
    }
    return SQLITE_ERROR;
}

void sqlite3_snapshot_free(sqlite3_snapshot *pSnapshot) {
    (void)pSnapshot;
}

int sqlite3_snapshot_cmp(sqlite3_snapshot *p1, sqlite3_snapshot *p2) {
    (void)p1;
    (void)p2;
    return SQLITE_ERROR;
}

#endif
