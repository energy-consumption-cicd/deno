# Energy measurement

Instrumentation for measuring the energy consumed by this project's CI cell. It
adds five files and modifies none of the upstream tree (`git diff` against
`denoland/deno` at `d5b1548eba893d4cc26305f33739a6ca2e6e8c11`, tag `v2.6.0`,
shows only them).

```
.github/workflows/energy-measurement.yml
energy-measurement/
|-- README.md
|-- Dockerfile
|-- run_pipeline.sh
`-- commands.sh
```

## Measured cell

`.github/workflows/ci.yml` is generated from `ci.generate.ts` and carries the
whole matrix in one job, `build` (`ci.yml:46`). The measured cell is the matrix
entry **Linux x86_64, debug profile, `job: test`** (`:108-113`,
`runs-on: ubuntu-24.04`, `use_sysroot: true`), in the regime of a push to
`main`: the `Build debug` step (`:394-398`) and the `Test (full, debug)` step
(`:556-564`), which runs one `cargo test` over the whole workspace. On a tag
push the cell runs `Test (fast, debug)` instead (`:565-574`); it is outside the
regime.

Release, macOS, Windows, aarch64, `bench`, `wpt`, `lint`, `libs` and the
publishing steps are outside the cell.

## Stages

| stage | commands | source |
|---|---|---|
| `build` | sysroot setup, version log, `cargo build --locked --all-targets --features=panic-trace` with `CARGO_PROFILE_DEV_DEBUG=0`, the two binary checks | `:251-331`, `:351-365`, `:394-398`, `:408-415` |
| `test` | sysroot setup, `cargo test --locked --features=panic-trace` with `CARGO_PROFILE_DEV_DEBUG=0` on the `target/` the build left | `:251-331`, `:556-564` |

Every command in `commands.sh` is literal. The differences against the job,
and no others:

| # | difference | why |
|---|---|---|
| D-1 | `~/.cargo` registry index and cache resolved at image build (`cargo fetch --locked` for the workspace and for `tests/sqlite_extension`, `registry/src` removed) | the job restores that cache (`:166-178`); the stages run with `--network none`; `sqlite_extension_test` builds `tests/sqlite_extension` with cargo at test time (`tests/sqlite_extension_test/tests/integration_tests.rs:24-34`) |
| D-2 | the prebuilt V8 142.2.0 static library is fetched at image build, sha256-verified, and passed through `RUSTY_V8_ARCHIVE` | the `v8` crate downloads it during `cargo build` and verifies no hash |
| D-3 | the typescript-go 0.1.11 build the test server fetches when it starts (`tests/util/server/src/servers/mod.rs:163,1533-1556`) is fetched at image build, sha256-verified against the hash `cli/tsc/go/tsgo_version.rs:28` pins, and laid out at the path the harness checks (`servers/mod.rs:1516-1531`) | every test points `DENO_TSGO_PATH` at it (`tests/util/server/src/builders.rs:871-875`); `--network none` |
| D-4 | checkout and the two submodules the job clones (`tests/util/std`, `tests/node_compat/runner/suite`) are copied into the image | standard in the study |
| D-5 | rustup 1.28.2 (the runner image's own), Rust 1.90.0 (from `rust-toolchain.toml`), Node 18.20.8 (`setup-node` 18, `:202-206`), Deno 2.5.6 (`setup-deno` v2.x, `:184-188`, the newest 2.x before the tag date) and Python 3.11.14 (`setup-python` 3.11, `:189-193`, the `actions/python-versions` build the runner tool cache holds) are installed at image build, sha256-verified; Python's `pip` upgrade of the tool-cache setup is skipped | runner toolchain setup; no measured command invokes `deno` or `python`, the version log reports them |
| D-6 | in the sysroot step, the four network lines (`apt.llvm.org` repository, key, `apt-get update`, `apt-get install`) are pre-baked and the `wget` of the sysroot tarball reads the image copy; the remaining lines, including `mount` and `chroot`, run verbatim. LLVM 20 comes from the `llvm-toolchain-jammy-20` index the step adds on the ubuntu-24.04 runner (`:263-270`), pinned to its single build (2025-07-08) | `--network none`; the container runs `--privileged` |
| D-7 | the container runs as `runner` with passwordless sudo, checkout at `/home/runner/work/deno/deno` | the sysroot step binds `/home` into the chroot |
| D-8 | `CI=true` in the image | Actions sets it in every job; the test harness reads it |
| D-9 | the build stage copies `target/` to a per-run volume and the test stage copies it back, the mechanism the earlier release branches use for their binaries, and the test container repeats the sysroot step | the two steps share one job and one filesystem; each stage runs in its own `--rm` container |
| D-10 | tests that reach external hosts fail under `--network none`: 7 tests of the `integration` target fail in the rehearsal (`node_unit_tests::{dns,http2,net,tls}_test`, `npm::lock_file_lock_write`, `check::ts_no_recheck_on_redirect`, `repl::pty_complete_imports_no_panic_empty_specifier`), the same ids in both repetitions, and `cargo test` stops after that target, so `specs`, `node_compat_tests` and the doctests do not run; the test stage exits 101 by pre-registration. `cargo test` stops at the first test target that fails, as the literal command does | no switch disables them without editing the upstream |
| D-12 | the `esbuild-x64` binary the test harness fetches when it starts its local npm registries (`tests/util/server/src/servers/npm_registry.rs:391-429`) is fetched at image build, sha256-verified, at the path the harness checks | without it the harness aborts every test target under `--network none` |
| D-14 | `.ms-playwright` (chromium and chromium-headless-shell 1148 of the tag's `playwright-core` 1.49.1) is installed at image build from sha256-verified archives, with the system libraries playwright lists for Ubuntu 24.04 | the job restores that directory from its cache (`:388-393`), and `npm/playwright_compat` runs at this tag |
| - | `GITHUB_ENV` writes are re-exported by `commands.sh` | a container has no runner to do it |

## Running

```
git submodule update --init --depth=1 -- tests/util/std tests/node_compat/runner/suite
docker build -t deno-measurement-2.6.0 -f energy-measurement/Dockerfile .
gh workflow run energy-measurement.yml --ref release-2.6.0 -f campaign=validation
gh workflow run energy-measurement.yml --ref release-2.6.0 -f campaign=full
```

`validation` runs run 0 only. `full` runs a discarded warm-up and then numbered
runs until 10 valid ones exist, and writes the medians. Each run rests 120 s to
measure the idle baseline; an idle package rate above 1.0 W aborts the run before
any stage (exit 90), since the bench is then not idle. Each stage runs under a
wall-clock ceiling (build 1774 s, test 1280 s, the larger
of 1.5x the largest known wall and that wall plus 15 s); a stage that reaches
it is killed with its container and the run exits 91 without a CSV, since a hung
harness is not a measurement. A run that produced no valid CSV (exit 90, 91, or
otherwise) is substituted by the next number, at most twice per campaign; a third
substitution ends the campaign as invalid. Every discarded run leaves a
`runs/discarded_<reason>_run_NN.txt` sidecar and a line in
`runs/execution_order.txt`. Exits 90 and 91 sit outside the workload's exit-code
list. `swap_run_NN_<stage>.txt` and `temp_run_NN_<stage>.txt` record host swap
counters and the package temperature read outside the measured window.

## Network

Both stages run under `--network none`. Every artifact the job fetches is
resolved at image build and verified by sha256: crates, the V8 static library,
the sysroot tarball, the typescript-go build, the harness's esbuild binary, the
playwright browser archives, rustup, Rust, Node, Deno and Python.
The test servers the suites use bind loopback ports only.
