# Everything the upstream jobs fetch from the network before the workload is
# resolved here, pinned by digest, so both measured stages run with --network none.
FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

ARG DEBIAN_FRONTEND=noninteractive

# The llvm-toolchain-noble-21 index of apt.llvm.org has not changed since before
# the tag date; the upstream step installs the same five packages unpinned
# (ci.yml:4032). libclang-21-dev serves bindgen (libsqlite3-sys, v8), which the
# hosted runner satisfies from its own clang.
ARG LLVM_VERSION=1:21.1.8~++20251221032922+2078da43e25a-1~exp1~20251221153059.70

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg xz-utils git sudo python3 \
      build-essential cmake ninja-build pkg-config; \
    echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-21 main" \
      > /etc/apt/sources.list.d/llvm-toolchain-noble-21.list; \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor \
      > /etc/apt/trusted.gpg.d/llvm-snapshot.gpg; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      "clang-21=${LLVM_VERSION}" "lld-21=${LLVM_VERSION}" \
      "clang-tools-21=${LLVM_VERSION}" "clang-format-21=${LLVM_VERSION}" \
      "clang-tidy-21=${LLVM_VERSION}" "libclang-21-dev=${LLVM_VERSION}"
# The package lists stay: the sysroot step's apt-get remove lines (verbatim in
# commands.sh) exit 100 without an index, and the hosted runner has one.

# The hosted runner executes the job as `runner` with passwordless sudo; the
# sysroot step (ci.yml:4014-4093) calls sudo on every privileged line.
RUN set -eux; \
    userdel -r ubuntu; \
    useradd -m -u 1000 runner; \
    echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner; \
    chmod 0440 /etc/sudoers.d/runner

# actions/setup-node resolves node-version 22 to the newest 22.x on the run
# date (ci.yml:4259-4263); pinned to the newest 22.x before the tag date.
ARG NODE_VERSION=22.22.0
ARG NODE_SHA256=9aa8e9d2298ab68c600bd6fb86a6c13bce11a4eca1ba9b39d79fa021755d7c37
RUN set -eux; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    ln -s /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /usr/local/bin/; \
    rm -f /tmp/node.tar.xz

# Artifacts the sysroot step and the v8 build script download at run time
# (ci.yml:4039; v8 145.0.0 build.rs static_lib_url). The v8 crate verifies no
# hash on its own; RUSTY_V8_ARCHIVE is the crate's documented local-file path.
ARG SYSROOT_SHA256=64513b04d8a38da6f47c0a9c4cb47b2ce7bcb735250b10eb10751aec6afe46ee
ARG V8_SHA256=7215753c0c78d141f752d7b993794bae07e18a1dfd466dcaa84fa64e76bacac1
RUN set -eux; \
    mkdir -p /opt/prebake; \
    curl -fsSL -o /opt/prebake/sysroot-x86_64.tar.xz \
      "https://github.com/denoland/deno_sysroot_build/releases/download/sysroot-20250207/sysroot-x86_64.tar.xz"; \
    echo "${SYSROOT_SHA256}  /opt/prebake/sysroot-x86_64.tar.xz" | sha256sum -c -; \
    curl -fsSL -o /opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz \
      "https://github.com/denoland/rusty_v8/releases/download/v145.0.0/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz"; \
    echo "${V8_SHA256}  /opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz" | sha256sum -c -

# Checkout with the two submodules the jobs clone (ci.yml:3982-3983,
# 4223-4228); wpt and lsp_benchdata are not cloned by either job.
COPY --chown=runner:runner . /home/runner/work/deno/deno
WORKDIR /home/runner/work/deno/deno
USER runner
ENV PATH=/home/runner/.cargo/bin:$PATH

# rustup 1.28.2, the one on the ubuntu-24.04 runner image of the tag date (the
# jobs have no rustup step), then the toolchain rust-toolchain.toml declares, as
# dsherret/rust-toolchain-file does (ci.yml:4013). rustup checks its own hashes.
ARG RUSTUP_SHA256=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -fsSL \
      "https://static.rust-lang.org/rustup/archive/1.28.2/x86_64-unknown-linux-gnu/rustup-init" \
      -o /tmp/rustup-init; \
    echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --default-toolchain none --no-modify-path; \
    rm -f /tmp/rustup-init; \
    rustup show; \
    rustc --version; cargo --version

# The crate cache the job restores (ci.yml:3984-3996) holds
# registry/index and registry/cache, not registry/src: unpacking stays in the stage.
# tests/sqlite_extension is excluded from the workspace and built by the
# integration suite at test time (tests/integration/sqlite_extension_tests.rs:17-38).
RUN set -eux; \
    cargo fetch --locked; \
    cargo fetch --locked --manifest-path tests/sqlite_extension/Cargo.toml; \
    rm -rf /home/runner/.cargo/registry/src

# The test harness downloads this esbuild binary when it starts the local npm
# registries (tests/util/server/servers/npm_registry.rs:405-429) and aborts
# every test crate if it cannot; the path is the one it checks first.
ARG ESBUILD_SHA256=3331e0b23c99d93d9a39e436a4838de40ca1c95ac3bcbd9874ba169d8545b634
RUN set -eux; \
    mkdir -p third_party/prebuilt/linux64; \
    curl -fsSL -o third_party/prebuilt/linux64/esbuild-x64 \
      "https://raw.githubusercontent.com/denoland/deno_third_party/d074edee0f4199f8226e1f87b88ccb7956d94454/prebuilt/linux64/esbuild-x64"; \
    echo "${ESBUILD_SHA256}  third_party/prebuilt/linux64/esbuild-x64" | sha256sum -c -; \
    chmod 0755 third_party/prebuilt/linux64/esbuild-x64

# The test server fetches this typescript-go build when it starts
# (tests/util/server/servers/mod.rs:154,1476-1507) and every test points
# DENO_TSGO_PATH at it (tests/util/lib/builders.rs:975-980); the hash is the one
# cli/tsc/go/tsgo_version.rs:36 pins, the path the one consts.rs:42-57 builds.
ARG TSGO_VERSION=0.1.19
ARG TSGO_SHA256=4089d04bf695155a0f7671c95b5b4ad68d2c424f88a924c52e5bc6b22735cec4
RUN set -eux; \
    curl -fsSL -o /tmp/tsgo.zip \
      "https://github.com/denoland/typescript-go/releases/download/v${TSGO_VERSION}/typescript-go-${TSGO_VERSION}-linux-x64.zip"; \
    echo "${TSGO_SHA256}  /tmp/tsgo.zip" | sha256sum -c -; \
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
      /tmp/tsgo.zip third_party/prebuilt/linux64; \
    mv third_party/prebuilt/linux64/tsgo "third_party/prebuilt/linux64/tsgo-${TSGO_VERSION}-linux-x64"; \
    chmod 0755 "third_party/prebuilt/linux64/tsgo-${TSGO_VERSION}-linux-x64"; \
    rm -f /tmp/tsgo.zip
# The LSP test client does not pass DENO_TSGO_PATH (tests/util/lib/lsp.rs:569-588), so the
# _tsgo LSP tests would download the same pinned build at test time; it is the one above.
ENV DENO_TSGO_PATH=/home/runner/work/deno/deno/third_party/prebuilt/linux64/tsgo-0.1.19-linux-x64

# The job restores ./.ms-playwright from its cache (ci.yml:4374-4379)
# and npm/playwright_compat runs at this tag; the tag's own playwright-core
# 1.49.1 installs it from verified archives served on loopback, with the
# libraries it lists for Ubuntu 24.04, which the hosted runner carries.
ARG PW_CHROMIUM_SHA256=7455d17b407bbcd1cc30c5bc8bc81fa4e67ac13635dbd5ca81f7824ec4b50439
ARG PW_HEADLESS_SHA256=43c8f1e29e089d9765ed83083ebbcaa7c7fe582aa762d0678f88838b55d92f63
ARG PW_FFMPEG_SHA256=f1f321f4502480b5531ca3d8db023a522c9f85c59183373699beb8680748299e
RUN set -eux; \
    b=/tmp/pw/builds; \
    mkdir -p "$b/chromium/1148" "$b/ffmpeg/1010" /tmp/pw/pkg; \
    curl -fsSL -o "$b/chromium/1148/chromium-linux.zip" \
      "https://cdn.playwright.dev/builds/chromium/1148/chromium-linux.zip"; \
    curl -fsSL -o "$b/chromium/1148/chromium-headless-shell-linux.zip" \
      "https://cdn.playwright.dev/builds/chromium/1148/chromium-headless-shell-linux.zip"; \
    curl -fsSL -o "$b/ffmpeg/1010/ffmpeg-linux.zip" \
      "https://cdn.playwright.dev/builds/ffmpeg/1010/ffmpeg-linux.zip"; \
    echo "${PW_CHROMIUM_SHA256}  $b/chromium/1148/chromium-linux.zip" | sha256sum -c -; \
    echo "${PW_HEADLESS_SHA256}  $b/chromium/1148/chromium-headless-shell-linux.zip" | sha256sum -c -; \
    echo "${PW_FFMPEG_SHA256}  $b/ffmpeg/1010/ffmpeg-linux.zip" | sha256sum -c -; \
    tar -xzf tests/registry/npm/playwright-core/playwright-core-1.49.1.tgz -C /tmp/pw/pkg; \
    (cd /tmp/pw && exec python3 -m http.server 8765 --bind 127.0.0.1) & srv=$!; \
    sleep 2; \
    PLAYWRIGHT_DOWNLOAD_HOST=http://127.0.0.1:8765 \
      PLAYWRIGHT_BROWSERS_PATH=/home/runner/work/deno/deno/.ms-playwright \
      node /tmp/pw/pkg/package/cli.js install --with-deps chromium; \
    kill "$srv"; \
    rm -rf /tmp/pw

# Job-level env (ci.yml:3969-3971); CI is set by Actions in every job
# and read by test_util::IS_CI (tests/util/lib/lib.rs:62).
ENV CI=true \
    CARGO_TERM_COLOR=always \
    RUST_BACKTRACE=full \
    RUST_LIB_BACKTRACE=0 \
    RUSTY_V8_ARCHIVE=/opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz \
    LIBCLANG_PATH=/usr/lib/llvm-21/lib
