#ifndef SQLITE_VIRTUAL_TABLE_SHIM_H
#define SQLITE_VIRTUAL_TABLE_SHIM_H

#include <sqlite3.h>

typedef struct SQLiteVirtualTable SQLiteVirtualTable;
typedef struct SQLiteVirtualCursor SQLiteVirtualCursor;

struct SQLiteVirtualTable {
    sqlite3_vtab base;
    void *swiftTable;
    void *moduleContext;
};

struct SQLiteVirtualCursor {
    sqlite3_vtab_cursor base;
    void *swiftCursor;
    SQLiteVirtualTable *table;
};

int SQLiteExtensionKit_CreateVirtualTableModule(sqlite3 *db, const char *name, void *context, void (*xDestroy)(void *));

void SQLiteExtensionKit_VirtualTableSetError(sqlite3_vtab *vtab, const char *message);

#endif /* SQLITE_VIRTUAL_TABLE_SHIM_H */
