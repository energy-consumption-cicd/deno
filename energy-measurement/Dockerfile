# Everything the upstream jobs fetch from the network before the workload is
# resolved here, pinned by digest, so both measured stages run with --network none.
FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

ARG DEBIAN_FRONTEND=noninteractive

# Snapshot of apt.llvm.org at image build time; the upstream step installs the
# same five packages unpinned (ci.generated.yml:5318). libclang-22-dev serves
# bindgen (libsqlite3-sys, v8), which the hosted runner satisfies from its own clang.
ARG LLVM_VERSION=1:22.1.8~++20260714014902+ca7933e47d3a-1~exp1~20260714135019.80

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg xz-utils git sudo python3 \
      build-essential cmake ninja-build pkg-config; \
    echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-22 main" \
      > /etc/apt/sources.list.d/llvm-toolchain-noble-22.list; \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor \
      > /etc/apt/trusted.gpg.d/llvm-snapshot.gpg; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      "clang-22=${LLVM_VERSION}" "lld-22=${LLVM_VERSION}" \
      "clang-tools-22=${LLVM_VERSION}" "clang-format-22=${LLVM_VERSION}" \
      "clang-tidy-22=${LLVM_VERSION}" "libclang-22-dev=${LLVM_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

# The hosted runner executes the job as `runner` with passwordless sudo; the
# sysroot step (ci.generated.yml:5299-5388) calls sudo on every privileged line.
RUN set -eux; \
    userdel -r ubuntu; \
    useradd -m -u 1000 runner; \
    echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner; \
    chmod 0440 /etc/sudoers.d/runner

# actions/setup-node resolves node-version 22 to the newest 22.x on the run
# date (ci.generated.yml:5561-5564); pinned here to the release current at build.
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
RUN set -eux; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    ln -s /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /usr/local/bin/; \
    rm -f /tmp/node.tar.xz

# Artifacts the sysroot step and the v8 build script download at run time
# (ci.generated.yml:5326; v8 build.rs static_lib_url). The v8 crate verifies no
# hash on its own; RUSTY_V8_ARCHIVE is the crate's documented local-file path.
ARG SYSROOT_SHA256=64513b04d8a38da6f47c0a9c4cb47b2ce7bcb735250b10eb10751aec6afe46ee
ARG V8_SHA256=f48762ca10d1f1fc605a441c5ae430ec8ce1e9e80f14d78fbc42cb878c30b476
RUN set -eux; \
    mkdir -p /opt/prebake; \
    curl -fsSL -o /opt/prebake/sysroot-x86_64.tar.xz \
      "https://github.com/denoland/deno_sysroot_build/releases/download/sysroot-20250207/sysroot-x86_64.tar.xz"; \
    echo "${SYSROOT_SHA256}  /opt/prebake/sysroot-x86_64.tar.xz" | sha256sum -c -; \
    curl -fsSL -o /opt/prebake/librusty_v8_simdutf_release_x86_64-unknown-linux-gnu.a.gz \
      "https://github.com/denoland/rusty_v8/releases/download/v150.4.0/librusty_v8_simdutf_release_x86_64-unknown-linux-gnu.a.gz"; \
    echo "${V8_SHA256}  /opt/prebake/librusty_v8_simdutf_release_x86_64-unknown-linux-gnu.a.gz" | sha256sum -c -

# Checkout with the two submodules the jobs clone (ci.generated.yml:5230-5231,
# 5524-5528); wpt, lsp_benchdata and lzld are not cloned by either job.
COPY --chown=runner:runner . /home/runner/work/deno/deno
WORKDIR /home/runner/work/deno/deno
USER runner
ENV PATH=/home/runner/.cargo/bin:$PATH

# rustup 1.28.2 as the upstream step installs it (ci.generated.yml:5261-5283),
# then the toolchain rust-toolchain.toml declares, as dsherret/rust-toolchain-file
# does (ci.generated.yml:5284). rustup checks its own component hashes.
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

# The crate cache the job restores (ci.generated.yml:5232-5244) holds
# registry/index and registry/cache, not registry/src: unpacking stays in the stage.
RUN set -eux; \
    cargo fetch --locked; \
    rm -rf /home/runner/.cargo/registry/src

# The native TypeScript compiler deno fetches during the test job
# (ci.generated.yml:5727-5734, cached at :5721-5726) is the npm package
# @typescript/typescript-linux-x64; laid out where tools/download_tsc.ts looks.
ARG TSC_VERSION=7.0.2
ARG TSC_SHA256=7ecad6f67377e831856367ab062ef394f21506a611405bf8ac0ff039348637d3
RUN set -eux; \
    curl -fsSL -o /tmp/tsc.tgz \
      "https://registry.npmjs.org/@typescript/typescript-linux-x64/-/typescript-linux-x64-${TSC_VERSION}.tgz"; \
    echo "${TSC_SHA256}  /tmp/tsc.tgz" | sha256sum -c -; \
    d=target/.native_tsc/deno_dir/tsc/${TSC_VERSION}/linux-x64; \
    mkdir -p "$d"; \
    tar -xzf /tmp/tsc.tgz -C "$d" --strip-components=1 package/lib; \
    test -x "$d/lib/tsc"; \
    rm -f /tmp/tsc.tgz

# Job-level env (ci.generated.yml:5217-5219); CI is set by Actions in every job
# and read by test_util::IS_CI (tests/util/lib/lib.rs:61).
ENV CI=true \
    CARGO_TERM_COLOR=always \
    RUST_BACKTRACE=full \
    RUST_LIB_BACKTRACE=0 \
    RUSTY_V8_ARCHIVE=/opt/prebake/librusty_v8_simdutf_release_x86_64-unknown-linux-gnu.a.gz \
    LIBCLANG_PATH=/usr/lib/llvm-22/lib
