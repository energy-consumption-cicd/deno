# Everything the upstream job fetches from the network before the workload is
# resolved here, pinned by digest, so both measured stages run with --network none.
FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

ARG DEBIAN_FRONTEND=noninteractive

# The sysroot step adds the llvm-toolchain-jammy-20 index of apt.llvm.org on the
# ubuntu-24.04 runner and installs the same five packages unpinned (ci.yml:275-282);
# the index carries a single amd64 build, dated 2025-07-08, before the tag date.
# libclang-20-dev serves bindgen (libsqlite3-sys, v8), which the hosted runner
# satisfies from its own clang.
ARG LLVM_VERSION=1:20.1.8~++20250708082409+6fb913d3e2ec-1~exp1~20250708202428.132

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg xz-utils git sudo python3 \
      build-essential cmake ninja-build pkg-config; \
    echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-20 main" \
      > /etc/apt/sources.list.d/llvm-toolchain-jammy-20.list; \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor \
      > /etc/apt/trusted.gpg.d/llvm-snapshot.gpg; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      "clang-20=${LLVM_VERSION}" "lld-20=${LLVM_VERSION}" \
      "clang-tools-20=${LLVM_VERSION}" "clang-format-20=${LLVM_VERSION}" \
      "clang-tidy-20=${LLVM_VERSION}" "libclang-20-dev=${LLVM_VERSION}"; \
    clang-20 --version | grep -F "clang version 20.1.8"
# The package lists stay: the sysroot step's apt-get remove lines (verbatim in
# commands.sh) exit 100 without an index, and the hosted runner has one.

# The hosted runner executes the job as `runner` with passwordless sudo; the
# sysroot step (ci.yml:263-343) calls sudo on every privileged line.
RUN set -eux; \
    userdel -r ubuntu; \
    useradd -m -u 1000 runner; \
    echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner; \
    chmod 0440 /etc/sudoers.d/runner

# actions/setup-node resolves node-version 18 to the newest 18.x on the run
# date (ci.yml:214-218); 18.20.8 is the last release of the line.
ARG NODE_VERSION=18.20.8
ARG NODE_SHA256=5467ee62d6af1411d46b6a10e3fb5cacc92734dbcef465fea14e7b90993001c9
RUN set -eux; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    ln -s /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /usr/local/bin/; \
    rm -f /tmp/node.tar.xz; \
    node --version | grep -F "v${NODE_VERSION}"

# denoland/setup-deno resolves deno-version v2.x to the newest 2.x release on
# the run date (ci.yml:196-200); pinned to the newest one published before the
# tag date. No measured command invokes it; the version log reports it.
ARG DENO_VERSION=2.4.5
ARG DENO_SHA256=6f9d8115bb3df582c0c5674507e906323b680be0f0b15e735d0cd5ec6be44444
RUN set -eux; \
    curl -fsSL -o /tmp/deno.zip \
      "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip"; \
    echo "${DENO_SHA256}  /tmp/deno.zip" | sha256sum -c -; \
    mkdir -p /opt/deno/bin; \
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
      /tmp/deno.zip /opt/deno/bin; \
    chmod 0755 /opt/deno/bin/deno; \
    ln -s /opt/deno/bin/deno /usr/local/bin/deno; \
    rm -f /tmp/deno.zip; \
    deno --version | grep -F "deno ${DENO_VERSION}"

# actions/setup-python selects the 3.11 line from the runner's tool cache
# (ci.yml:201-205), populated from the actions/python-versions builds; pinned to
# the newest 3.11 build before the tag date, at the tool cache path it was built
# for. No measured command invokes it; the version log reports it.
ARG PYTHON_VERSION=3.11.13
ARG PYTHON_BUILD=15433298024
ARG PYTHON_SHA256=bf58712e13464122707e63d8913f17aaeff63293ee4c0cee11ce9f76b188fab6
RUN set -eux; \
    d="/opt/hostedtoolcache/Python/${PYTHON_VERSION}/x64"; \
    curl -fsSL -o /tmp/python.tar.gz \
      "https://github.com/actions/python-versions/releases/download/${PYTHON_VERSION}-${PYTHON_BUILD}/python-${PYTHON_VERSION}-linux-24.04-x64.tar.gz"; \
    echo "${PYTHON_SHA256}  /tmp/python.tar.gz" | sha256sum -c -; \
    mkdir -p "$d"; \
    tar -xzf /tmp/python.tar.gz -C "$d"; \
    rm -f "$d/setup.sh" /tmp/python.tar.gz; \
    ln -s ./bin/python3.11 "$d/python"; \
    ln -s python3.11 "$d/bin/python311"; \
    [ -e "$d/bin/python" ] || ln -s python3.11 "$d/bin/python"; \
    "$d/bin/python" --version | grep -F "Python ${PYTHON_VERSION}"

# Artifacts the sysroot step and the v8 build script download at run time
# (ci.yml:289; v8 140.0.0 build.rs static_lib_url). The v8 crate verifies no
# hash on its own; RUSTY_V8_ARCHIVE is the crate's documented local-file path.
ARG SYSROOT_SHA256=64513b04d8a38da6f47c0a9c4cb47b2ce7bcb735250b10eb10751aec6afe46ee
ARG V8_SHA256=c101ef9eb38f129febb3e615dcd15c7eaf9783e5e8bb160e0fccdebfe6e3247c
RUN set -eux; \
    mkdir -p /opt/prebake; \
    curl -fsSL -o /opt/prebake/sysroot-x86_64.tar.xz \
      "https://github.com/denoland/deno_sysroot_build/releases/download/sysroot-20250207/sysroot-x86_64.tar.xz"; \
    echo "${SYSROOT_SHA256}  /opt/prebake/sysroot-x86_64.tar.xz" | sha256sum -c -; \
    curl -fsSL -o /opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz \
      "https://github.com/denoland/rusty_v8/releases/download/v140.0.0/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz"; \
    echo "${V8_SHA256}  /opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz" | sha256sum -c -

# Checkout with the two submodules the job clones (ci.yml:158-160, 164-166);
# wpt and lsp_benchdata are not cloned by the cell.
COPY --chown=runner:runner . /home/runner/work/deno/deno
WORKDIR /home/runner/work/deno/deno
USER runner
ENV PATH=/home/runner/.cargo/bin:/opt/hostedtoolcache/Python/3.11.13/x64/bin:/opt/hostedtoolcache/Python/3.11.13/x64:$PATH

# rustup 1.28.2, the one on the ubuntu-24.04 runner image of the tag date (the
# job has no rustup step), then the toolchain rust-toolchain.toml declares, as
# dsherret/rust-toolchain-file does (ci.yml:194). rustup checks its own hashes.
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
    rustc --version | grep -F "rustc 1.89.0"; cargo --version

# The crate cache the job restores (ci.yml:181-193) holds registry/index and
# registry/cache, not registry/src: unpacking stays in the stage. The sqlite
# extension of this tag (tests/sqlite_extension_test) is a workspace member.
RUN set -eux; \
    cargo fetch --locked; \
    rm -rf /home/runner/.cargo/registry/src

# The test harness downloads this esbuild binary when it starts the local npm
# registries (tests/util/server/src/servers/npm_registry.rs:383-421) and aborts
# every test target if it cannot; the path is the one it checks first.
ARG ESBUILD_SHA256=3331e0b23c99d93d9a39e436a4838de40ca1c95ac3bcbd9874ba169d8545b634
RUN set -eux; \
    mkdir -p third_party/prebuilt/linux64; \
    curl -fsSL -o third_party/prebuilt/linux64/esbuild-x64 \
      "https://raw.githubusercontent.com/denoland/deno_third_party/de0d517e6f703fb4735b7aa5806f69fbdbb1d907/prebuilt/linux64/esbuild-x64"; \
    echo "${ESBUILD_SHA256}  third_party/prebuilt/linux64/esbuild-x64" | sha256sum -c -; \
    chmod 0755 third_party/prebuilt/linux64/esbuild-x64

# The job restores ./.ms-playwright from its cache (ci.yml:400-405)
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

# Job-level env (ci.yml:142-145); CI is set by Actions in every job and read
# by the test harness.
ENV CI=true \
    CARGO_TERM_COLOR=always \
    RUST_BACKTRACE=full \
    RUST_LIB_BACKTRACE=0 \
    RUSTY_V8_ARCHIVE=/opt/prebake/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz \
    LIBCLANG_PATH=/usr/lib/llvm-20/lib
