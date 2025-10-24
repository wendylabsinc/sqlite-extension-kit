# Android Integration

Integrate Swift-based SQLite extensions into Android applications.

## Overview

Android can use SQLite extensions, but since SQLiteExtensionKit is written in Swift, you need to bridge between Swift and Java/Kotlin through JNI (Java Native Interface). This guide covers two approaches: using Swift for Android or creating a C wrapper.

## Approach 1: Swift for Android (Experimental)

Swift for Android is under active development. This approach compiles Swift code directly for Android.

### Prerequisites

- Swift 6.0 or later with Android toolchain
- Android NDK r25 or later
- Android SDK with API level 21+

### Step 1: Set Up Swift for Android

```bash
# Install Swift for Android toolchain
# Follow: https://github.com/swiftlang/swift/blob/main/docs/Android.md

# Verify installation
swiftc --version
```

### Step 2: Configure Build for Android

Create `Package.swift` for Android build:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyExtension",
    platforms: [.android(api: 21)],
    products: [
        .library(
            name: "MyExtension",
            type: .static,
            targets: ["MyExtension"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/wendylabsinc/sqlite-extension-kit", from: "0.0.2")
    ],
    targets: [
        .target(
            name: "MyExtension",
            dependencies: ["SQLiteExtensionKit"]
        )
    ]
)
```

### Step 3: Build for Android Architectures

```bash
# Build for different Android ABIs
swift build -c release \
  --triple aarch64-unknown-linux-android \
  --sdk $ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64

swift build -c release \
  --triple armv7-unknown-linux-android \
  --sdk $ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64

swift build -c release \
  --triple x86_64-unknown-linux-android \
  --sdk $ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64
```

### Step 4: Create JNI Wrapper

Create a JNI wrapper in C to bridge Java/Kotlin to Swift:

```c
// jni_wrapper.c
#include <jni.h>
#include <sqlite3.h>

// Import Swift function
extern int registerMyExtension(sqlite3* db);

JNIEXPORT jint JNICALL
Java_com_example_myapp_SQLiteExtensions_registerExtension(
    JNIEnv* env,
    jobject thiz,
    jlong db_pointer
) {
    sqlite3* db = (sqlite3*)db_pointer;
    return registerMyExtension(db);
}
```

Expose Swift registration to C:

```swift
// In your Swift extension file
@_cdecl("registerMyExtension")
public func registerMyExtension(_ db: OpaquePointer) -> Int32 {
    do {
        let database = SQLiteDatabase(db)
        try MyExtension.register(with: database)
        return 0  // Success
    } catch {
        return 1  // Error
    }
}
```

## Approach 2: C Wrapper (Recommended)

For production use, create a pure C wrapper that can be easily integrated with Android.

### Step 1: Create C Wrapper Layer

```c
// my_extension_wrapper.c
#include <sqlite3.h>
#include <string.h>

// C implementation of your extension
static void my_func_impl(
    sqlite3_context* context,
    int argc,
    sqlite3_value** argv
) {
    const char* result = "Hello from C!";
    sqlite3_result_text(context, result, -1, SQLITE_TRANSIENT);
}

// Registration function
int register_my_extension(sqlite3* db) {
    int rc = sqlite3_create_function(
        db,
        "my_func",
        0,  // argc
        SQLITE_UTF8 | SQLITE_DETERMINISTIC,
        NULL,
        my_func_impl,
        NULL,
        NULL
    );
    return rc;
}

// JNI wrapper
JNIEXPORT jint JNICALL
Java_com_example_myapp_SQLiteExtensions_registerExtension(
    JNIEnv* env,
    jobject thiz,
    jlong db_pointer
) {
    sqlite3* db = (sqlite3*)db_pointer;
    return register_my_extension(db);
}
```

### Step 2: Create Android.mk

```makefile
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := my_extension
LOCAL_SRC_FILES := my_extension_wrapper.c
LOCAL_LDLIBS := -llog
include $(BUILD_SHARED_LIBRARY)
```

Or use CMake (`CMakeLists.txt`):

```cmake
cmake_minimum_required(VERSION 3.10)
project(MyExtension)

add_library(my_extension SHARED
    my_extension_wrapper.c
)

target_link_libraries(my_extension
    log
)
```

### Step 3: Build with Android NDK

```bash
# Using ndk-build
cd jni
ndk-build

# Or using CMake
mkdir build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21
make
```

### Step 4: Create Kotlin/Java Interface

```kotlin
// SQLiteExtensions.kt
package com.example.myapp

import android.database.sqlite.SQLiteDatabase

object SQLiteExtensions {
    init {
        System.loadLibrary("my_extension")
    }

    /**
     * Register the SQLite extension with the database.
     *
     * @param db SQLiteDatabase instance
     * @return 0 on success, non-zero on error
     */
    external fun registerExtension(dbPointer: Long): Int

    /**
     * Helper to get database pointer from SQLiteDatabase
     */
    private fun getDatabasePointer(db: SQLiteDatabase): Long {
        // Use reflection to get native pointer
        val field = SQLiteDatabase::class.java.getDeclaredField("mNativeHandle")
        field.isAccessible = true
        return field.getLong(db)
    }

    /**
     * Register extension with SQLiteDatabase instance
     */
    fun register(db: SQLiteDatabase): Boolean {
        val pointer = getDatabasePointer(db)
        return registerExtension(pointer) == 0
    }
}
```

### Step 5: Use in Android App

```kotlin
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class MyDatabaseHelper(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    DATABASE_VERSION
) {
    override fun onCreate(db: SQLiteDatabase) {
        // Register extension when database is created
        if (!SQLiteExtensions.register(db)) {
            throw RuntimeException("Failed to register SQLite extension")
        }

        // Now you can use the extension
        db.execSQL("CREATE TABLE test (id INTEGER, value TEXT)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Handle upgrades
    }

    fun testExtension() {
        readableDatabase.use { db ->
            val cursor = db.rawQuery("SELECT my_func()", null)
            cursor.use {
                if (it.moveToFirst()) {
                    val result = it.getString(0)
                    println("Extension result: $result")
                }
            }
        }
    }
}
```

## Using with Room Database

Integrate with Android's Room persistence library:

```kotlin
import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [User::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao

    companion object {
        fun build(context: Context): AppDatabase {
            return Room.databaseBuilder(
                context,
                AppDatabase::class.java,
                "app-database"
            )
            .addCallback(object : Callback() {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    super.onCreate(db)
                    // Register extension on database creation
                    registerExtensionWithRoom(db)
                }

                override fun onOpen(db: SupportSQLiteDatabase) {
                    super.onOpen(db)
                    // Re-register on each open
                    registerExtensionWithRoom(db)
                }
            })
            .build()
        }

        private fun registerExtensionWithRoom(db: SupportSQLiteDatabase) {
            // Get native pointer through reflection
            val dbField = db.javaClass.getDeclaredField("mDelegate")
            dbField.isAccessible = true
            val delegate = dbField.get(db)

            val connField = delegate.javaClass.getDeclaredField("mConnection")
            connField.isAccessible = true
            val connection = connField.get(delegate)

            val handleField = connection.javaClass.getDeclaredField("mConnectionPtr")
            handleField.isAccessible = true
            val handle = handleField.getLong(connection)

            SQLiteExtensions.registerExtension(handle)
        }
    }
}
```

## Gradle Configuration

Add to your `app/build.gradle`:

```groovy
android {
    defaultConfig {
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
        }
    }

    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}
```

## Testing on Android

Create instrumented tests:

```kotlin
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SQLiteExtensionTest {
    @Test
    fun testExtensionFunction() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val helper = MyDatabaseHelper(context)
        val db = helper.writableDatabase

        val cursor = db.rawQuery("SELECT my_func()", null)
        cursor.use {
            assert(it.moveToFirst())
            val result = it.getString(0)
            assert(result == "Hello from C!")
        }
    }
}
```

## Common Issues

### UnsatisfiedLinkError

If you get "library not found" errors:

1. Verify `.so` files are in correct directory: `src/main/jniLibs/<ABI>/`
2. Check library name matches `System.loadLibrary()` call
3. Ensure all ABIs are built

### Method Not Found

If JNI methods aren't found:

1. Verify JNI function signatures match exactly
2. Check `javah` or `javac -h` generated headers
3. Ensure native library is loaded before use

### Database Corruption

If database becomes corrupted:

1. Only register extensions on main database instance
2. Don't call registration multiple times
3. Ensure thread-safe access to database

## Performance Considerations

- **Static linking**: Link extension statically for better performance
- **ProGuard**: Add rules to keep extension classes:

```proguard
-keep class com.example.myapp.SQLiteExtensions { *; }
-keepclassmembers class com.example.myapp.SQLiteExtensions { *; }
```

- **ABI filtering**: Only include necessary ABIs to reduce APK size

## Distribution

### AAR Library

Package as an Android Archive:

```gradle
// library/build.gradle
android {
    defaultConfig {
        consumerProguardFiles 'consumer-rules.pro'
    }
}
```

Then publish:

```bash
./gradlew assembleRelease
# AAR is at: library/build/outputs/aar/library-release.aar
```

### Maven Central

Publish to Maven Central for easy distribution:

```gradle
plugins {
    id 'maven-publish'
    id 'signing'
}

publishing {
    publications {
        release(MavenPublication) {
            groupId = 'com.example'
            artifactId = 'sqlite-extension'
            version = '1.0.0'

            from components.release
        }
    }
}
```

## Next Steps

- See <doc:iOSIntegration> for iOS static library approach
- Learn about <doc:LinuxDeployment> for server deployments
- Explore <doc:AdvancedFunctions> for complex extension features
