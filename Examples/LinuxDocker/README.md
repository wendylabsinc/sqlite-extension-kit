# Linux Docker Demo

This container shows how to build and exercise the `SQLiteExtensionKit` loadable extensions
against the system `libsqlite3` on Linux.

## Build the Image

```bash
docker build -f Examples/LinuxDocker/Dockerfile -t sqlite-extension-kit-demo .
```

## Run the Demo

```bash
docker run --rm sqlite-extension-kit-demo
```

The container runs the package test suite, builds the `ExampleExtensions` product in release
mode, and executes the `LinuxDockerDemo` program. The demo process links against the system
`libsqlite3`, registers the Swift implementations of the string helper functions, and executes a
few queries to showcase the results.
