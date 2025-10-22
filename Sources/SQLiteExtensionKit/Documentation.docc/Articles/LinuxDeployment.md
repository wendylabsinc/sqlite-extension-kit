# Linux Deployment

Deploy SQLite extensions as loadable libraries on Linux systems.

## Overview

Linux provides the most straightforward deployment model for SQLite extensions. You can build loadable `.so` (shared object) files that SQLite can load at runtime using the standard `load_extension()` function.

## Prerequisites

### System Requirements

- Linux distribution (Ubuntu, Debian, RHEL, etc.)
- Swift 6.0 or later
- SQLite 3.x with extension loading enabled
- GCC or Clang compiler

### Install Dependencies

#### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install -y \
    libsqlite3-dev \
    sqlite3 \
    build-essential
```

#### RHEL/CentOS/Fedora

```bash
sudo yum install -y \
    sqlite-devel \
    sqlite \
    gcc \
    make
```

#### Arch Linux

```bash
sudo pacman -S sqlite gcc make
```

## Building for Linux

### Step 1: Configure Package

Your `Package.swift` should specify dynamic library type:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyExtension",
    products: [
        .library(
            name: "MyExtension",
            type: .dynamic,
            targets: ["MyExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/SQLiteExtensionKit", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: ["SQLiteExtensionKit"]
        )
    ]
)
```

### Step 2: Build the Extension

```bash
# Build in release mode
swift build -c release

# The extension will be at:
# .build/release/libMyExtension.so
```

### Step 3: Verify the Build

```bash
# Check that it's a shared library
file .build/release/libMyExtension.so
# Output: ELF 64-bit LSB shared object, x86-64...

# Check exported symbols
nm -D .build/release/libMyExtension.so | grep init
# Output: ... T sqlite3_myextension_init

# Check dependencies
ldd .build/release/libMyExtension.so
```

## Loading Extensions in SQLite

### Method 1: SQLite CLI

```bash
# Start SQLite
sqlite3 mydata.db

# Load the extension
sqlite> .load .build/release/libMyExtension.so

# Use the extension functions
sqlite> SELECT my_func();
```

### Method 2: SQL Statement

```sql
-- Enable extension loading (if not already enabled)
PRAGMA compile_options;  -- Check for ENABLE_LOAD_EXTENSION

-- Load the extension
SELECT load_extension('.build/release/libMyExtension.so');

-- Use the functions
SELECT my_func();
```

### Method 3: C API

```c
#include <sqlite3.h>
#include <stdio.h>

int main() {
    sqlite3 *db;
    char *err_msg = NULL;

    // Open database
    if (sqlite3_open("mydata.db", &db) != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        return 1;
    }

    // Enable extension loading
    sqlite3_enable_load_extension(db, 1);

    // Load the extension
    if (sqlite3_load_extension(db, ".build/release/libMyExtension.so", NULL, &err_msg) != SQLITE_OK) {
        fprintf(stderr, "Cannot load extension: %s\n", err_msg);
        sqlite3_free(err_msg);
        return 1;
    }

    // Use the extension
    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, "SELECT my_func()", -1, &stmt, NULL);
    sqlite3_step(stmt);

    const unsigned char *result = sqlite3_column_text(stmt, 0);
    printf("Result: %s\n", result);

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
```

Compile and run:

```bash
gcc -o test test.c -lsqlite3
./test
```

## Deployment Strategies

### Strategy 1: System-Wide Installation

Install the extension globally:

```bash
# Copy to system library path
sudo cp .build/release/libMyExtension.so /usr/local/lib/

# Update library cache
sudo ldconfig

# Load from anywhere
sqlite3 mydata.db ".load libMyExtension"
```

### Strategy 2: Application Bundle

Bundle with your application:

```
myapp/
├── bin/
│   └── myapp
├── lib/
│   └── libMyExtension.so
└── data/
    └── myapp.db
```

Use relative path:

```bash
# Set LD_LIBRARY_PATH
export LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH
./bin/myapp
```

### Strategy 3: Docker Container

Create a Dockerfile:

```dockerfile
FROM swift:6.0-focal

# Install SQLite
RUN apt-get update && apt-get install -y \
    sqlite3 \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source
WORKDIR /app
COPY . .

# Build extension
RUN swift build -c release

# Install extension
RUN cp .build/release/libMyExtension.so /usr/local/lib/
RUN ldconfig

# Run application
CMD ["sqlite3", "/data/app.db"]
```

Build and run:

```bash
docker build -t myapp-with-extension .
docker run -v $(pwd)/data:/data myapp-with-extension
```

## Server Deployment

### Apache + mod_wsgi (Python)

```python
import sqlite3
import os

# Get extension path
EXTENSION_PATH = os.path.join(
    os.path.dirname(__file__),
    'lib/libMyExtension.so'
)

def get_db():
    db = sqlite3.connect('/var/www/data/app.db')
    db.enable_load_extension(True)
    db.load_extension(EXTENSION_PATH)
    db.enable_load_extension(False)
    return db

def application(environ, start_response):
    db = get_db()
    cursor = db.execute("SELECT my_func()")
    result = cursor.fetchone()[0]

    output = f'Result: {result}'
    response_headers = [('Content-type', 'text/plain')]
    start_response('200 OK', response_headers)
    return [output.encode('utf-8')]
```

### Nginx + uWSGI

uwsgi.ini:

```ini
[uwsgi]
module = app:application
master = true
processes = 4

# Set library path
env = LD_LIBRARY_PATH=/app/lib:$LD_LIBRARY_PATH

socket = /tmp/uwsgi.sock
chmod-socket = 666
vacuum = true
```

### systemd Service

Create `/etc/systemd/system/myapp.service`:

```ini
[Unit]
Description=My Application with SQLite Extension
After=network.target

[Service]
Type=simple
User=myapp
WorkingDirectory=/opt/myapp
Environment="LD_LIBRARY_PATH=/opt/myapp/lib"
ExecStart=/opt/myapp/bin/myapp
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable myapp
sudo systemctl start myapp
```

## Security Considerations

### File Permissions

Set appropriate permissions:

```bash
# Extension library
chmod 644 /usr/local/lib/libMyExtension.so
chown root:root /usr/local/lib/libMyExtension.so

# Database file
chmod 660 /var/lib/myapp/data.db
chown myapp:myapp /var/lib/myapp/data.db
```

### Extension Loading Control

Limit extension loading:

```c
// Only allow specific extensions
int load_trusted_extension(sqlite3 *db, const char *path) {
    // Verify extension path
    if (strstr(path, "..") != NULL) {
        return SQLITE_ERROR;  // Prevent directory traversal
    }

    // Check extension is in trusted directory
    if (strncmp(path, "/usr/local/lib/", 15) != 0) {
        return SQLITE_ERROR;
    }

    sqlite3_enable_load_extension(db, 1);
    int rc = sqlite3_load_extension(db, path, NULL, NULL);
    sqlite3_enable_load_extension(db, 0);

    return rc;
}
```

### SELinux/AppArmor

Configure security modules:

```bash
# SELinux: Allow extension loading
sudo semanage fcontext -a -t lib_t "/usr/local/lib/libMyExtension.so"
sudo restorecon -v /usr/local/lib/libMyExtension.so

# AppArmor: Add to profile
/usr/local/lib/libMyExtension.so r,
```

## Performance Optimization

### Build with Optimizations

```bash
# Build with aggressive optimizations
swift build -c release -Xswiftc -O -Xswiftc -whole-module-optimization

# Strip debug symbols
strip .build/release/libMyExtension.so
```

### Preload Extension

For frequently used extensions:

```c
// Preload into shared memory
#include <dlfcn.h>

void *handle = dlopen("/usr/local/lib/libMyExtension.so", RTLD_NOW | RTLD_GLOBAL);
if (handle == NULL) {
    fprintf(stderr, "Cannot preload: %s\n", dlerror());
}
```

### Connection Pooling

Use connection pooling to avoid repeated loading:

```python
from sqlite3 import connect
from contextlib import contextmanager

class ConnectionPool:
    def __init__(self, db_path, extension_path, pool_size=5):
        self.db_path = db_path
        self.extension_path = extension_path
        self.pool = []
        for _ in range(pool_size):
            conn = self._create_connection()
            self.pool.append(conn)

    def _create_connection(self):
        conn = connect(self.db_path, check_same_thread=False)
        conn.enable_load_extension(True)
        conn.load_extension(self.extension_path)
        conn.enable_load_extension(False)
        return conn

    @contextmanager
    def get_connection(self):
        conn = self.pool.pop()
        try:
            yield conn
        finally:
            self.pool.append(conn)
```

## Monitoring and Logging

### Check Extension Load

```sql
-- Verify extension is loaded
SELECT * FROM pragma_function_list WHERE name = 'my_func';
```

### Log Extension Usage

Add logging to extension:

```swift
import Foundation

try db.createScalarFunction(name: "my_func") { context, args in
    // Log usage
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] my_func called with \(args.count) args")

    // Implementation
    context.result("result")
}
```

### Monitor Performance

```bash
# Use strace to monitor extension loading
strace -e open,openat sqlite3 mydata.db ".load libMyExtension.so"

# Profile with perf
perf record -g sqlite3 mydata.db
perf report
```

## Troubleshooting

### Extension Not Found

```bash
# Check library search path
echo $LD_LIBRARY_PATH

# Find the extension
find / -name "libMyExtension.so" 2>/dev/null

# Use absolute path
sqlite3 mydata.db ".load /full/path/to/libMyExtension.so"
```

### Symbol Errors

```
Error: /path/to/libMyExtension.so: undefined symbol: swift_retain
```

Solution: Ensure Swift runtime is available:

```bash
# Check Swift runtime location
ldconfig -p | grep swift

# Add Swift lib path
export LD_LIBRARY_PATH=/usr/lib/swift/linux:$LD_LIBRARY_PATH
```

### Version Conflicts

If multiple SQLite versions exist:

```bash
# Check SQLite version
sqlite3 --version

# Check compiled version
strings libMyExtension.so | grep sqlite

# Use LD_PRELOAD if needed
LD_PRELOAD=/usr/local/lib/libsqlite3.so.0 sqlite3
```

## Next Steps

- See <doc:WindowsDeployment> for Windows-specific deployment
- Learn about <doc:DeploymentGuide> for general deployment strategies
- Explore <doc:AdvancedFunctions> for complex extension features
