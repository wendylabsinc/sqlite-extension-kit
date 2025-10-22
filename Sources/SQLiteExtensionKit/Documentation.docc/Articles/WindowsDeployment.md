# Windows Deployment

Deploy SQLite extensions as loadable DLL files on Windows systems.

## Overview

Windows supports SQLite extensions as DLL (Dynamic Link Library) files. This guide covers building Swift-based extensions for Windows using the Swift toolchain for Windows.

## Prerequisites

### System Requirements

- Windows 10 or later (64-bit)
- Visual Studio 2022 or later
- Swift 6.0 for Windows
- SQLite for Windows

### Install Dependencies

#### Install Swift for Windows

Download and install from [swift.org/download](https://swift.org/download):

```powershell
# Download Swift installer
# Run the installer and add Swift to PATH

# Verify installation
swift --version
```

#### Install Visual Studio

Install Visual Studio 2022 with C++ development tools:

- Desktop development with C++
- Windows 10 SDK
- MSVC v143 or later

#### Install SQLite

```powershell
# Download SQLite DLL and tools
Invoke-WebRequest -Uri "https://www.sqlite.org/2024/sqlite-dll-win64-x64-3450000.zip" -OutFile sqlite-dll.zip
Invoke-WebRequest -Uri "https://www.sqlite.org/2024/sqlite-tools-win32-x86-3450000.zip" -OutFile sqlite-tools.zip

# Extract
Expand-Archive sqlite-dll.zip -DestinationPath C:\sqlite
Expand-Archive sqlite-tools.zip -DestinationPath C:\sqlite

# Add to PATH
$env:PATH += ";C:\sqlite"
```

## Building for Windows

### Step 1: Configure Package

Create `Package.swift` for Windows build:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyExtension",
    platforms: [
        .windows(.v10)
    ],
    products: [
        .library(
            name: "MyExtension",
            type: .dynamic,
            targets: ["MyExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/wendylabsinc/sqlite-extension-kit", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: ["SQLiteExtensionKit"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
```

### Step 2: Build the Extension

Open Developer Command Prompt for Visual Studio:

```powershell
# Build in release mode
swift build -c release

# The extension will be at:
# .build\x86_64-unknown-windows-msvc\release\MyExtension.dll
```

### Step 3: Verify the Build

```powershell
# Check that it's a DLL
dumpbin /headers .build\x86_64-unknown-windows-msvc\release\MyExtension.dll

# Check exported symbols
dumpbin /exports .build\x86_64-unknown-windows-msvc\release\MyExtension.dll | findstr init

# Check dependencies
dumpbin /dependents .build\x86_64-unknown-windows-msvc\release\MyExtension.dll
```

## Loading Extensions on Windows

### Method 1: SQLite CLI

```powershell
# Start SQLite
sqlite3 mydata.db

# Load the extension
sqlite> .load .build\x86_64-unknown-windows-msvc\release\MyExtension.dll

# Use the extension functions
sqlite> SELECT my_func();
```

### Method 2: C API

```c
#include <sqlite3.h>
#include <stdio.h>
#include <windows.h>

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
    const char *ext_path = ".build\\x86_64-unknown-windows-msvc\\release\\MyExtension.dll";
    if (sqlite3_load_extension(db, ext_path, NULL, &err_msg) != SQLITE_OK) {
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

Compile with Visual Studio:

```powershell
cl /EHsc test.c sqlite3.lib
test.exe
```

## Deployment Strategies

### Strategy 1: Application Bundle

Bundle the DLL with your application:

```
MyApp\
├── MyApp.exe
├── MyExtension.dll
├── sqlite3.dll
└── data\
    └── app.db
```

Load from application directory:

```c
// Get executable directory
char exe_path[MAX_PATH];
GetModuleFileNameA(NULL, exe_path, MAX_PATH);
char *last_slash = strrchr(exe_path, '\\');
if (last_slash) *last_slash = '\0';

// Build extension path
char ext_path[MAX_PATH];
sprintf(ext_path, "%s\\MyExtension.dll", exe_path);

// Load extension
sqlite3_load_extension(db, ext_path, NULL, NULL);
```

### Strategy 2: System-Wide Installation

Install to System32 (requires administrator):

```powershell
# Copy to System32
Copy-Item MyExtension.dll C:\Windows\System32\

# Load from anywhere
sqlite3 mydata.db ".load MyExtension"
```

### Strategy 3: Windows Service

Create a Windows service:

```c
// service.c
#include <windows.h>
#include <sqlite3.h>

SERVICE_STATUS g_ServiceStatus = {0};
SERVICE_STATUS_HANDLE g_StatusHandle = NULL;

void WINAPI ServiceMain(DWORD argc, LPTSTR *argv);
void WINAPI ServiceCtrlHandler(DWORD);

int main(int argc, char *argv[]) {
    SERVICE_TABLE_ENTRY ServiceTable[] = {
        {TEXT("MyService"), (LPSERVICE_MAIN_FUNCTION)ServiceMain},
        {NULL, NULL}
    };

    if (!StartServiceCtrlDispatcher(ServiceTable)) {
        return GetLastError();
    }

    return 0;
}

void WINAPI ServiceMain(DWORD argc, LPTSTR *argv) {
    g_StatusHandle = RegisterServiceCtrlHandler(TEXT("MyService"), ServiceCtrlHandler);

    g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

    // Initialize SQLite with extension
    sqlite3 *db;
    sqlite3_open("C:\\ProgramData\\MyApp\\data.db", &db);
    sqlite3_enable_load_extension(db, 1);
    sqlite3_load_extension(db, "C:\\Program Files\\MyApp\\MyExtension.dll", NULL, NULL);

    // Service logic here
    while (g_ServiceStatus.dwCurrentState == SERVICE_RUNNING) {
        Sleep(1000);
    }

    sqlite3_close(db);
}

void WINAPI ServiceCtrlHandler(DWORD CtrlCode) {
    switch (CtrlCode) {
        case SERVICE_CONTROL_STOP:
            g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
            SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
            break;
    }
}
```

Install the service:

```powershell
# Create service
sc create MyService binPath= "C:\Path\To\service.exe"

# Start service
sc start MyService
```

## .NET Integration

### Using System.Data.SQLite

Install NuGet package:

```powershell
Install-Package System.Data.SQLite
```

Load extension in C#:

```csharp
using System.Data.SQLite;

class Program {
    static void Main() {
        var connectionString = "Data Source=mydata.db;Version=3;";

        using (var connection = new SQLiteConnection(connectionString)) {
            connection.Open();

            // Enable extension loading
            connection.EnableExtensions(true);

            // Load the extension
            connection.LoadExtension("MyExtension.dll");

            // Use the extension
            using (var command = new SQLiteCommand("SELECT my_func()", connection)) {
                var result = command.ExecuteScalar();
                Console.WriteLine($"Result: {result}");
            }
        }
    }
}
```

### Using Microsoft.Data.Sqlite

Install NuGet package:

```powershell
Install-Package Microsoft.Data.Sqlite
```

```csharp
using Microsoft.Data.Sqlite;

class Program {
    static void Main() {
        using (var connection = new SqliteConnection("Data Source=mydata.db")) {
            connection.Open();

            // Load extension using raw API
            var db = connection.Handle;
            NativeMethods.sqlite3_enable_load_extension(db, 1);

            var rc = NativeMethods.sqlite3_load_extension(
                db,
                "MyExtension.dll",
                IntPtr.Zero,
                out IntPtr errMsg
            );

            if (rc != 0) {
                var error = Marshal.PtrToStringAnsi(errMsg);
                NativeMethods.sqlite3_free(errMsg);
                throw new Exception($"Failed to load extension: {error}");
            }

            // Use the extension
            using (var command = connection.CreateCommand()) {
                command.CommandText = "SELECT my_func()";
                var result = command.ExecuteScalar();
                Console.WriteLine($"Result: {result}");
            }
        }
    }
}
```

## PowerShell Integration

Use SQLite from PowerShell:

```powershell
# Install PSSQLite module
Install-Module PSSQLite -Force

# Use SQLite with extension
Import-Module PSSQLite

$db = New-SQLiteConnection -DataSource "mydata.db"

# Load extension (requires custom function)
$null = Invoke-SqliteQuery -SQLiteConnection $db -Query "SELECT load_extension('MyExtension.dll')"

# Use extension
$result = Invoke-SqliteQuery -SQLiteConnection $db -Query "SELECT my_func()"
Write-Host "Result: $($result.Column1)"

Close-SQLiteConnection -SQLiteConnection $db
```

## IIS Deployment

### ASP.NET Application

web.config:

```xml
<?xml version="1.0"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" />
    </handlers>
  </system.webServer>

  <system.web>
    <trust level="Full" />
  </system.web>
</configuration>
```

Application code:

```csharp
public class Startup {
    public void Configure(IApplicationBuilder app) {
        // Set DLL directory
        var basePath = AppDomain.CurrentDomain.BaseDirectory;
        Environment.SetEnvironmentVariable(
            "PATH",
            $"{basePath};{Environment.GetEnvironmentVariable("PATH")}"
        );

        app.Run(async (context) => {
            using (var connection = new SqliteConnection("Data Source=app.db")) {
                connection.Open();
                connection.EnableExtensions(true);
                connection.LoadExtension(Path.Combine(basePath, "MyExtension.dll"));

                using (var command = new SqliteCommand("SELECT my_func()", connection)) {
                    var result = command.ExecuteScalar();
                    await context.Response.WriteAsync($"Result: {result}");
                }
            }
        });
    }
}
```

## Security Considerations

### Code Signing

Sign your DLL:

```powershell
# Get certificate
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert

# Sign DLL
Set-AuthenticodeSignature -FilePath MyExtension.dll -Certificate $cert
```

### Access Control

Set file permissions:

```powershell
# Set ACL
$acl = Get-Acl MyExtension.dll
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Users",
    "Read,Execute",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl MyExtension.dll $acl
```

### Firewall Rules

If extension makes network calls:

```powershell
New-NetFirewallRule -DisplayName "MyApp SQLite Extension" `
    -Direction Outbound `
    -Program "C:\Path\To\MyApp.exe" `
    -Action Allow
```

## Performance Optimization

### Build Optimizations

```powershell
# Build with optimizations
swift build -c release -Xswiftc -O -Xswiftc -whole-module-optimization

# Strip if possible (limited support on Windows)
# Use dumpbin to verify optimizations
```

### Preloading

```c
// Preload DLL into process
HMODULE handle = LoadLibrary(TEXT("MyExtension.dll"));
if (handle == NULL) {
    DWORD error = GetLastError();
    fprintf(stderr, "Cannot preload: %lu\n", error);
}
```

## Troubleshooting

### DLL Not Found

```
Error: unable to open database file
```

Solutions:

```powershell
# Check DLL location
where MyExtension.dll

# Add to PATH
$env:PATH += ";C:\Path\To\Extension"

# Use absolute path
sqlite3 mydata.db ".load C:\Full\Path\To\MyExtension.dll"
```

### Missing Dependencies

```
Error: The specified module could not be found
```

Check dependencies:

```powershell
# Use Dependency Walker or dumpbin
dumpbin /dependents MyExtension.dll

# Common missing: Swift runtime DLLs
# Ensure Swift bin directory is in PATH
```

### Version Conflicts

```powershell
# Check SQLite version
sqlite3 --version

# Verify DLL matches
dumpbin /exports sqlite3.dll | findstr sqlite3_version
```

## Distribution

### Installer (WiX Toolset)

Create MSI installer:

```xml
<?xml version="1.0"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="MyApp" Version="1.0.0" Manufacturer="Company">
    <Package InstallerVersion="200" Compressed="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLDIR" Name="MyApp">
          <Component Id="MainExecutable">
            <File Source="MyApp.exe" />
            <File Source="MyExtension.dll" />
            <File Source="sqlite3.dll" />
          </Component>
        </Directory>
      </Directory>
    </Directory>

    <Feature Id="Complete" Level="1">
      <ComponentRef Id="MainExecutable" />
    </Feature>
  </Product>
</Wix>
```

Build installer:

```powershell
candle MyApp.wxs
light MyApp.wixobj -out MyApp.msi
```

### Chocolatey Package

Create package:

```powershell
# Create package directory
mkdir myapp-package

# Create nuspec
@"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">
  <metadata>
    <id>myapp</id>
    <version>1.0.0</version>
    <description>My Application with SQLite Extension</description>
  </metadata>
</package>
"@ | Out-File myapp-package\myapp.nuspec

# Pack
choco pack myapp-package\myapp.nuspec
```

## Next Steps

- See <doc:LinuxDeployment> for Linux-specific deployment
- Learn about <doc:DeploymentGuide> for general deployment strategies
- Explore <doc:AdvancedFunctions> for complex extension features
