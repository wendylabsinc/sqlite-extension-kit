FROM swift:6.0-jammy

WORKDIR /workspace/sqlite-extension-kit

# Install SQLite without bundling it with the project so we link against the system library.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        sqlite3 \
        libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

# First copy the manifest to leverage build caching.
COPY Package.swift ./

# Then copy sources and tests required for building ExampleExtensions.
COPY Sources ./Sources
COPY Tests ./Tests
COPY Examples ./Examples
COPY README.md ./README.md

# Build the extension once during image build so the runtime command is fast.
RUN swift build -c release --product ExampleExtensions

# Provide the demonstration script.
COPY Examples/LinuxDocker/run.sh /workspace/sqlite-extension-kit/run.sh

RUN chmod +x /workspace/sqlite-extension-kit/run.sh

CMD ["/workspace/sqlite-extension-kit/run.sh"]
