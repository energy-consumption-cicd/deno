#!/usr/bin/env bash

# Literal transcription of the measured steps of the `build` job of ci.yml at
# c6adba122836aeddd92800c45282897e1f508bd3 (tag v2.5.0, generated from
# ci.generate.ts), matrix cell test / debug / linux-x86_64 (:108-113), in the
# regime of a push to main: build is the Build debug step (:422-426), test is
# the Test (full, debug) step (:597-605). Line references are to the generated
# file; the template line is given where the generated text comes from ci.generate.ts.

# GitHub runs every `run:` block under `bash -eo pipefail` (defaults.run.shell).
set -euo pipefail
STAGE="${1:?stage required: build | test}"

# GITHUB_WORKSPACE of the hosted runner; the sysroot step binds /home into the
# chroot, so the checkout has to live under it for :443 to resolve.
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

# ci.yml:263-343 (template ci.generate.ts:79-162). The four network lines
# (apt.llvm.org repository, key, update, install) are pre-baked in the image,
# and the sysroot tarball comes from the image instead of wget (D-6); every
# other line is verbatim, including the trailing `cd` that makes $(pwd)
# resolve to $HOME in the thinlto-cache-dir argument. The job runs it once;
# each stage container runs it, since the job state does not cross containers.
sysroot_step() {
  # Setting up sysroot
  export DEBIAN_FRONTEND=noninteractive
  # Avoid running man-db triggers, which sometimes takes several minutes
  # to complete.
  sudo apt-get -qq remove --purge -y man-db > /dev/null 2> /dev/null
  # Remove older clang before we install
  sudo apt-get -qq remove   'clang-12*' 'clang-13*' 'clang-14*' 'clang-15*' 'clang-16*' 'clang-17*' 'clang-18*' 'clang-19*' 'llvm-12*' 'llvm-13*' 'llvm-14*' 'llvm-15*' 'llvm-16*' 'llvm-17*' 'llvm-18*' 'llvm-19*' 'lld-12*' 'lld-13*' 'lld-14*' 'lld-15*' 'lld-16*' 'lld-17*' 'lld-18*' 'lld-19*' > /dev/null 2> /dev/null

  # Install clang-XXX, lld-XXX, and debootstrap.
  # :275-282 (repository, key, apt-get update, apt-get install) pre-baked in the image (D-6)
  # Fix alternatives
  (yes '' | sudo update-alternatives --force --all) > /dev/null 2> /dev/null || true

  clang-20 -c -o /tmp/memfd_create_shim.o tools/memfd_create_shim.c -fPIC

  echo "Decompressing sysroot..."
  # :289 wget replaced by the image copy, verified by sha256 at image build (D-6)
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
  -C linker=clang-20
  -C link-arg=-fuse-ld=lld-20
  -C link-arg=-ldl
  -C link-arg=-Wl,--allow-shlib-undefined
  -C link-arg=-Wl,--thinlto-cache-dir=$(pwd)/target/release/lto-cache
  -C link-arg=-Wl,--thinlto-cache-policy,cache_size_bytes=700m
  -C link-arg=/tmp/memfd_create_shim.o
  --cfg tokio_unstable
  $RUSTFLAGS
__1
RUSTDOCFLAGS<<__1
  -C linker-plugin-lto=true
  -C linker=clang-20
  -C link-arg=-fuse-ld=lld-20
  -C link-arg=-ldl
  -C link-arg=-Wl,--allow-shlib-undefined
  -C link-arg=-Wl,--thinlto-cache-dir=$(pwd)/target/release/lto-cache
  -C link-arg=-Wl,--thinlto-cache-policy,cache_size_bytes=700m
  -C link-arg=/tmp/memfd_create_shim.o
  --cfg tokio_unstable
  $RUSTFLAGS
__1
CC=/usr/bin/clang-20
CFLAGS=$CFLAGS
" > $GITHUB_ENV
  cd /home/runner/work/deno/deno
  apply_github_env
}

case "$STAGE" in

  build)
    # :263-343 Set up incremental LTO and sysroot build
    sysroot_step

    # :363-377 Log versions, before the build at this tag
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

    # :422-426 Build debug (template ci.generate.ts:713-715)
    CARGO_PROFILE_DEV_DEBUG=0 \
      cargo build --locked --all-targets --features=panic-trace

    # :436-440 Check deno binary
    NO_COLOR=1 target/debug/deno eval "console.log(1+2)" | grep 3

    # :441-443 Check deno binary (in sysroot)
    sudo chroot /sysroot "$(pwd)/target/debug/deno" --version

    # The job keeps target/ on the same filesystem for the Test step; the test
    # stage runs in its own --rm container, so the hand-off is a copy to a
    # per-run volume, as the earlier release branches do with their binaries (D-9).
    cp -a target/. /artifacts/
    ;;

  test)
    # :263-343 Set up incremental LTO and sysroot build, the job state the Test
    # step inherits (D-9)
    sysroot_step

    # The target/ the Build step left, copied back from the per-run volume (D-9)
    mkdir -p target
    cp -a /artifacts/. target/

    # :597-605 Test (full, debug) (template ci.generate.ts:982), on the target/
    # the build stage left (D-9)
    echo "=== cargo test: start $(date -u +%FT%TZ) ==="
    set +e
    CARGO_PROFILE_DEV_DEBUG=0 \
      cargo test --locked --features=panic-trace
    STAGE_EXIT=$?
    set -e
    echo "=== cargo test: end $(date -u +%FT%TZ) exit=${STAGE_EXIT} ==="

    # :624-626 Ensure no git changes runs on pull_request only

    exit "$STAGE_EXIT"
    ;;

  *)
    echo "unknown stage: $STAGE" >&2
    exit 2
    ;;

esac
