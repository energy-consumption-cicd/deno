#!/usr/bin/env bash

# Literal transcription of the two measured jobs of ci.generated.yml at
# fbb5be31ac23ef40f51025d6aeaaa91d9f082e4a (tag v2.8.0, generated from ci.ts):
# build is build-debug-linux-x86_64 (:4665), test is test-debug-linux-x86_64
# (:4904) with its five matrix entries run in sequence, as shard 0 does on a
# push to main. Line references are to the generated file; the template line
# is given where the generated text comes from ci.ts.

# GitHub runs every `run:` block under `bash -eo pipefail` (defaults.run.shell).
set -euo pipefail
STAGE="${1:?stage required: build | test}"

# GITHUB_WORKSPACE of the hosted runner; the sysroot step binds /home into the
# chroot, so the checkout has to live under it for :4862 to resolve.
cd /home/runner/work/deno/deno

# Between steps the runner re-exports everything written to GITHUB_ENV; the
# two syntaxes it accepts are `KEY=value` and `KEY<<DELIM ... DELIM`.
GITHUB_ENV=/tmp/github_env
: > "$GITHUB_ENV"
apply_github_env() {
  local line key delim value
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)\<\<(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"; delim="${BASH_REMATCH[2]}"; value=""
      while IFS= read -r line && [[ "$line" != "$delim" ]]; do
        value+="${line}"$'\n'
      done
      export "$key=${value%$'\n'}"
    elif [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    fi
  done < "$GITHUB_ENV"
}

# ci.generated.yml:4760-4852 and :5045-5138 (template ci.ts:120-214). The four
# network lines (apt.llvm.org repository, key, update, install) are pre-baked in
# the image, and the sysroot tarball comes from the image instead of wget (D-6);
# every other line is verbatim, including the trailing `cd` that makes
# $(pwd) resolve to $HOME in the thinlto-cache-dir argument.
sysroot_step() {
  local llvmVersion=22
  # Setting up sysroot
  export DEBIAN_FRONTEND=noninteractive
  # Avoid running man-db triggers, which sometimes takes several minutes
  # to complete.
  sudo apt-get -qq remove --purge -y man-db > /dev/null 2> /dev/null
  # Remove older clang before we install
  sudo apt-get -qq remove   'clang-12*' 'clang-13*' 'clang-14*' 'clang-15*' 'clang-16*' 'clang-17*' 'clang-18*' 'clang-19*' 'clang-20*' 'clang-21*' 'llvm-12*' 'llvm-13*' 'llvm-14*' 'llvm-15*' 'llvm-16*' 'llvm-17*' 'llvm-18*' 'llvm-19*' 'llvm-20*' 'llvm-21*' 'lld-12*' 'lld-13*' 'lld-14*' 'lld-15*' 'lld-16*' 'lld-17*' 'lld-18*' 'lld-19*' 'lld-20*' 'lld-21*' > /dev/null 2> /dev/null

  # Install clang-XXX, lld-XXX, and debootstrap.
  # :4771-4778 (repository, key, apt-get update, apt-get install) pre-baked in the image (D-6)
  # Fix alternatives
  (yes '' | sudo update-alternatives --force --all) > /dev/null 2> /dev/null || true

  clang-22 -c -o /tmp/memfd_create_shim.o tools/memfd_create_shim.c -fPIC
  clang-22 -c -o /tmp/glibc_math_shim.o tools/glibc_math_shim.c -fPIC

  echo "Decompressing sysroot..."
  # :4786 wget replaced by the image copy, verified by sha256 at image build (D-6)
  cp /opt/prebake/sysroot-`uname -m`.tar.xz /tmp/sysroot.tar.xz
  cd /
  xzcat /tmp/sysroot.tar.xz | sudo tar -x
  sudo mount --rbind /dev /sysroot/dev
  sudo mount --rbind /sys /sysroot/sys
  sudo mount --rbind /home /sysroot/home
  sudo mount -t proc /proc /sysroot/proc
  cd

  echo "Done."

  # Configure the build environment. Both Rust and Clang will produce
  # llvm bitcode only, so we can use lld's incremental LTO support.

  # Load the sysroot's env vars
  echo "sysroot env:"
  cat /sysroot/.env
  . /sysroot/.env

  # Important notes:
  #   1. -ldl seems to be required to avoid a failure in FFI tests. This flag seems
  #      to be in the Rust default flags in the smoketest, so uncertain why we need
  #      to be explicit here.
  #   2. RUSTFLAGS and RUSTDOCFLAGS must be specified, otherwise the doctests fail
  #      to build because the object formats are not compatible.
  echo "
CARGO_PROFILE_BENCH_INCREMENTAL=false
CARGO_PROFILE_RELEASE_INCREMENTAL=false
RUSTFLAGS<<__1
  -C linker-plugin-lto=true
  -C linker=clang-${llvmVersion}
  -C link-arg=-fuse-ld=lld-${llvmVersion}
  -C link-arg=-ldl
  -C link-arg=-Wl,--allow-shlib-undefined
  -C link-arg=-Wl,--thinlto-cache-dir=$(pwd)/target/release/lto-cache
  -C link-arg=-Wl,--thinlto-cache-policy,cache_size_bytes=700m
  -C link-arg=/tmp/memfd_create_shim.o
  -C link-arg=/tmp/glibc_math_shim.o
  -C link-arg=-Wl,--wrap=expf
  -C link-arg=-Wl,--wrap=powf
  -C link-arg=-Wl,--wrap=exp2f
  -C link-arg=-Wl,--wrap=log2f
  -C link-arg=-Wl,--wrap=logf
  --cfg tokio_unstable
  $RUSTFLAGS
__1
RUSTDOCFLAGS<<__1
  -C linker-plugin-lto=true
  -C linker=clang-${llvmVersion}
  -C link-arg=-fuse-ld=lld-${llvmVersion}
  -C link-arg=-ldl
  -C link-arg=-Wl,--allow-shlib-undefined
  -C link-arg=-Wl,--thinlto-cache-dir=$(pwd)/target/release/lto-cache
  -C link-arg=-Wl,--thinlto-cache-policy,cache_size_bytes=700m
  -C link-arg=/tmp/memfd_create_shim.o
  -C link-arg=/tmp/glibc_math_shim.o
  -C link-arg=-Wl,--wrap=expf
  -C link-arg=-Wl,--wrap=powf
  -C link-arg=-Wl,--wrap=exp2f
  -C link-arg=-Wl,--wrap=log2f
  -C link-arg=-Wl,--wrap=logf
  --cfg tokio_unstable
  $RUSTFLAGS
__1
CC=/usr/bin/clang-${llvmVersion}
CFLAGS=$CFLAGS
" > $GITHUB_ENV
  cd /home/runner/work/deno/deno
  apply_github_env
}

case "$STAGE" in

  build)
    # :4746-4759 Log versions
    echo '*** Python'
    command -v python && python --version || echo 'No python found or bad executable'
    echo '*** Rust'
    command -v rustc && rustc --version || echo 'No rustc found or bad executable'
    echo '*** Cargo'
    command -v cargo && cargo --version || echo 'No cargo found or bad executable'
    echo '*** Deno'
    command -v deno && deno --version || echo 'No deno found or bad executable'
    echo '*** Node'
    command -v node && node --version || echo 'No node found or bad executable'
    echo '*** Installed packages'
    command -v dpkg && dpkg -l || echo 'No dpkg found or bad executable'

    # :4760-4852 Set up incremental LTO and sysroot build
    sysroot_step

    # :4853-4856 Build debug (template ci.ts:921-924)
    CARGO_PROFILE_DEV_DEBUG=0 \
      cargo build --locked --bin deno --bin denort --bin test_server --features=panic-trace

    # :4857-4860 Check deno binary
    NO_COLOR=1 target/debug/deno eval "console.log(1+2)" | grep 3

    # :4861-4862 Check deno binary (in sysroot) (template ci.ts:937)
    sudo chroot /sysroot "$(pwd)/target/debug/deno" --version

    # :4863-4880 Upload artifact x3: the test stage runs in its own --rm
    # container, so the hand-off is a copy to a per-run volume (D-9).
    cp target/debug/deno target/debug/denort target/debug/test_server /artifacts/
    ;;

  test)
    # :5045-5138 Set up incremental LTO and sysroot build
    sysroot_step

    # :5139-5165 Download artifact x3 and set permissions (D-9)
    mkdir -p target/debug
    cp /artifacts/deno /artifacts/denort /artifacts/test_server target/debug/
    chmod +x target/debug/deno
    chmod +x target/debug/denort
    chmod +x target/debug/test_server

    # :5175-5181 (template ci.ts:1172). Every crate runs to completion; the
    # stage exits with the first non-zero code, as the vision commands.sh does,
    # so one failing crate never truncates the workload of the others.
    STAGE_EXIT=0
    run_crate() {
      local test_package="$1" test_crate="$2" rc
      echo "=== cargo test --test ${test_crate}: start $(date -u +%FT%TZ) ==="
      set +e
      # CI_SHARD_INDEX and CI_SHARD_TOTAL are set only for pull_request (:5179-5180).
      CARGO_PROFILE_DEV_DEBUG=0 CI_SHARD_INDEX= CI_SHARD_TOTAL= \
        cargo test -p "$test_package" --test "$test_crate"
      rc=$?
      set -e
      echo "=== cargo test --test ${test_crate}: end $(date -u +%FT%TZ) exit=${rc} ==="
      if [ "$rc" -ne 0 ] && [ "$STAGE_EXIT" -eq 0 ]; then
        STAGE_EXIT="$rc"
      fi
      return 0
    }

    # Matrix order (:4914-4960)
    run_crate integration_tests integration

    run_crate node_compat_tests node_compat

    # :5172-5174 Build ffi (debug), on the specs entry only
    cargo build -p test_ffi
    run_crate specs_tests specs

    run_crate unit_tests unit

    run_crate unit_node_tests unit_node

    # :5182-5184 Ensure no git changes runs on pull_request only

    echo "=== stage test: aggregate exit=${STAGE_EXIT} ==="
    exit "$STAGE_EXIT"
    ;;

  *)
    echo "unknown stage: $STAGE" >&2
    exit 2
    ;;

esac
