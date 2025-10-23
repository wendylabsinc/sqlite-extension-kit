#include "SQLiteVirtualTable.h"
#include <stddef.h>

extern int SQLiteExtensionKit_VirtualTableCreate(
    void *context,
    sqlite3 *db,
    int argc,
    const char *const *argv,
    SQLiteVirtualTable **outTable,
    char **pzErr,
    int isCreate
);

extern int SQLiteExtensionKit_VirtualTableBestIndex(
    SQLiteVirtualTable *table,
    sqlite3_index_info *info
);

extern int SQLiteExtensionKit_VirtualTableDisconnect(SQLiteVirtualTable *table);
extern int SQLiteExtensionKit_VirtualTableDestroy(SQLiteVirtualTable *table);

extern int SQLiteExtensionKit_VirtualTableOpen(
    SQLiteVirtualTable *table,
    SQLiteVirtualCursor **outCursor
);

extern int SQLiteExtensionKit_VirtualTableClose(SQLiteVirtualCursor *cursor);

extern int SQLiteExtensionKit_VirtualTableFilter(
    SQLiteVirtualCursor *cursor,
    int idxNum,
    const char *idxStr,
    sqlite3_value **argv,
    int argc
);

extern int SQLiteExtensionKit_VirtualTableNext(SQLiteVirtualCursor *cursor);
extern int SQLiteExtensionKit_VirtualTableEof(SQLiteVirtualCursor *cursor);

extern int SQLiteExtensionKit_VirtualTableColumn(
    SQLiteVirtualCursor *cursor,
    sqlite3_context *context,
    int column
);

extern int SQLiteExtensionKit_VirtualTableRowid(
    SQLiteVirtualCursor *cursor,
    sqlite3_int64 *rowid
);

static int swiftCreate(
    sqlite3 *db,
    void *context,
    int argc,
    const char *const *argv,
    sqlite3_vtab **ppVTab,
    char **pzErr,
    int isCreate
) {
    SQLiteVirtualTable *table = NULL;
    int rc = SQLiteExtensionKit_VirtualTableCreate(
        context,
        db,
        argc,
        argv,
        &table,
        pzErr,
        isCreate
    );

    if (rc == SQLITE_OK) {
        *ppVTab = (sqlite3_vtab *)table;
    }

    return rc;
}

static int swiftCreateThunk(
    sqlite3 *db,
    void *context,
    int argc,
    const char *const *argv,
    sqlite3_vtab **ppVTab,
    char **pzErr
) {
    return swiftCreate(db, context, argc, argv, ppVTab, pzErr, 1);
}

static int swiftConnectThunk(
    sqlite3 *db,
    void *context,
    int argc,
    const char *const *argv,
    sqlite3_vtab **ppVTab,
    char **pzErr
) {
    return swiftCreate(db, context, argc, argv, ppVTab, pzErr, 0);
}

static int swiftBestIndex(sqlite3_vtab *pVTab, sqlite3_index_info *info) {
    return SQLiteExtensionKit_VirtualTableBestIndex(
        (SQLiteVirtualTable *)pVTab,
        info
    );
}

static int swiftDisconnect(sqlite3_vtab *pVTab) {
    return SQLiteExtensionKit_VirtualTableDisconnect((SQLiteVirtualTable *)pVTab);
}

static int swiftDestroy(sqlite3_vtab *pVTab) {
    return SQLiteExtensionKit_VirtualTableDestroy((SQLiteVirtualTable *)pVTab);
}

static int swiftOpen(sqlite3_vtab *pVTab, sqlite3_vtab_cursor **ppCursor) {
    SQLiteVirtualCursor *cursor = NULL;
    int rc = SQLiteExtensionKit_VirtualTableOpen(
        (SQLiteVirtualTable *)pVTab,
        &cursor
    );

    if (rc == SQLITE_OK) {
        *ppCursor = (sqlite3_vtab_cursor *)cursor;
    }

    return rc;
}

static int swiftClose(sqlite3_vtab_cursor *pCursor) {
    return SQLiteExtensionKit_VirtualTableClose((SQLiteVirtualCursor *)pCursor);
}

static int swiftFilter(
    sqlite3_vtab_cursor *pCursor,
    int idxNum,
    const char *idxStr,
    int argc,
    sqlite3_value **argv
) {
    return SQLiteExtensionKit_VirtualTableFilter(
        (SQLiteVirtualCursor *)pCursor,
        idxNum,
        idxStr,
        argv,
        argc
    );
}

static int swiftNext(sqlite3_vtab_cursor *pCursor) {
    return SQLiteExtensionKit_VirtualTableNext((SQLiteVirtualCursor *)pCursor);
}

static int swiftEof(sqlite3_vtab_cursor *pCursor) {
    return SQLiteExtensionKit_VirtualTableEof((SQLiteVirtualCursor *)pCursor);
}

static int swiftColumn(
    sqlite3_vtab_cursor *pCursor,
    sqlite3_context *context,
    int column
) {
    return SQLiteExtensionKit_VirtualTableColumn(
        (SQLiteVirtualCursor *)pCursor,
        context,
        column
    );
}

static int swiftRowid(sqlite3_vtab_cursor *pCursor, sqlite3_int64 *rowid) {
    return SQLiteExtensionKit_VirtualTableRowid(
        (SQLiteVirtualCursor *)pCursor,
        rowid
    );
}

static const sqlite3_module SwiftVirtualTableModule = {
    1,                      /* iVersion */
    swiftCreateThunk,       /* xCreate */
    swiftConnectThunk,      /* xConnect */
    swiftBestIndex,         /* xBestIndex */
    swiftDisconnect,        /* xDisconnect */
    swiftDestroy,           /* xDestroy */
    swiftOpen,              /* xOpen */
    swiftClose,             /* xClose */
    swiftFilter,            /* xFilter */
    swiftNext,              /* xNext */
    swiftEof,               /* xEof */
    swiftColumn,            /* xColumn */
    swiftRowid,             /* xRowid */
    NULL,                   /* xUpdate */
    NULL,                   /* xBegin */
    NULL,                   /* xSync */
    NULL,                   /* xCommit */
    NULL,                   /* xRollback */
    NULL,                   /* xFindFunction */
    NULL,                   /* xRename */
    NULL,                   /* xSavepoint */
    NULL,                   /* xRelease */
    NULL                    /* xRollbackTo */
};

int SQLiteExtensionKit_CreateVirtualTableModule(
    sqlite3 *db,
    const char *name,
    void *context,
    void (*xDestroy)(void *)
) {
    return sqlite3_create_module_v2(db, name, &SwiftVirtualTableModule, context, xDestroy);
}

void SQLiteExtensionKit_VirtualTableSetError(sqlite3_vtab *vtab, const char *message) {
    if (!vtab) {
        return;
    }

    sqlite3_free(vtab->zErrMsg);
    vtab->zErrMsg = sqlite3_mprintf("%s", message ? message : "Virtual table error");
}
