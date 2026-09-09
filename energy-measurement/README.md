# Energy measurement

Instrumentation for measuring the energy consumed by this project's CI cell. It
adds five files and modifies none of the upstream tree (`git diff` against
`denoland/deno` at `60e01b1dabc1fce03ccd819a01796b52496671a4` shows only them).

```
.github/workflows/energy-measurement.yml
energy-measurement/
├── README.md
├── Dockerfile
├── run_pipeline.sh
└── commands.sh
```

## Measured cell

`.github/workflows/ci.generated.yml` is generated from `ci.ts` and carries the
whole matrix. The measured cell is **Linux x86_64, debug profile**, in the regime
of a push to `main`:

- `build-debug-linux-x86_64` (`ci.generated.yml:5204`), `runs-on: ubuntu-24.04`;
- `test-debug-linux-x86_64` (`ci.generated.yml:5450`), whose five matrix entries
  (`integration`, `node_compat`, `specs`, `unit`, `unit_node`) run here in
  sequence. On a push to `main` only shard 0 of each crate runs the tests
  (`:5739`, `:5742-5743`), and it runs the whole crate.

Release, macOS, Windows, aarch64, `wpt`, `bench`, `lint`, `deno-core-*` and
the publishing jobs are outside the cell.

## Stages

| stage | commands | source |
|---|---|---|
| `build` | sysroot setup, `cargo build --locked -p deno -p denort -p test_server …` with `CARGO_PROFILE_DEV_DEBUG=0`, the two binary checks, hand-off of the three binaries | `:5299-5388`, `:5395-5408`, `:5409-5426` |
| `test` | sysroot setup, reception of the binaries, `tools/download_tsc.ts`, `cargo build -p test_ffi`, five `cargo test -p <package> --test <crate>` | `:5591-5687`, `:5688-5714`, `:5727-5744` |

Every command in `commands.sh` is literal. The differences against the jobs,
and no others:

| # | difference | why |
|---|---|---|
| D-1 | `~/.cargo` registry index and cache resolved at image build (`cargo fetch --locked`, `registry/src` removed) | the job restores that cache (`:5232-5244`); the stages run with `--network none` |
| D-2 | the prebuilt V8 static library is fetched at image build, sha256-verified, and passed through `RUSTY_V8_ARCHIVE` | the `v8` crate downloads it during `cargo build` and verifies no hash |
| D-3 | `@typescript/typescript-linux-x64@7.0.2` is fetched at image build and laid out under `target/.native_tsc/deno_dir` | `deno` downloads it during the test job; the job caches that directory (`:5721-5726`) |
| D-4 | checkout and the two submodules the jobs clone are copied into the image | standard in the study |
| D-5 | rustup 1.28.2, Rust 1.95.0 (from `rust-toolchain.toml`) and Node 22 are installed at image build, sha256-verified | runner toolchain setup |
| D-6 | in the sysroot step, the four network lines (`apt.llvm.org` repository, key, `apt-get update`, `apt-get install`) are pre-baked and the `wget` of the sysroot tarball reads the image copy; the remaining lines, including `mount` and `chroot`, run verbatim | `--network none`; the container runs `--privileged` |
| D-7 | the container runs as `runner` with passwordless sudo, checkout at `/home/runner/work/deno/deno` | the sysroot step binds `/home` into the chroot |
| D-8 | `CI=true` in the image | Actions sets it in every job; `test_util::IS_CI` reads it |
| D-9 | upload/download-artifact become a copy through a per-run volume | each stage runs in its own `--rm` container |
| D-10 | `tests/integration/npm_tests.rs:819` (`lock_file_lock_write`) and `tests/unit_node/tls_test.ts:712` reach external hosts and fail under `--network none`; the test stage exits 101 by pre-registration | no switch disables them without editing the upstream |
| D-12 | the `esbuild-x64` binary the test harness fetches when it starts its local npm registries (`tests/util/server/servers/npm_registry.rs:536-560`) is fetched at image build, sha256-verified, at the path the harness checks | without it the harness aborts every test crate under `--network none` |
| — | `Check QuickJS backend` (`:5399-5402`) is not run | `cargo check` of an alternative backend absent from the measured binary |
| — | `GITHUB_ENV` writes are re-exported by `commands.sh` | a container has no runner to do it |

## Running

```
docker build -t deno-medicao -f energy-measurement/Dockerfile .
gh workflow run energy-measurement.yml -f campaign=validation
gh workflow run energy-measurement.yml -f campaign=full
```

`validation` runs run 0 only. `full` runs a discarded warm-up and then numbered
runs until 10 valid ones exist, and writes the medians. Each run rests 120 s to
measure the idle baseline; an idle package rate above 1.0 W aborts the run before
any stage (exit 90), since the bench is then not idle. Each stage runs under a
wall-clock ceiling (build 1000 s, test 3600 s, about 1.5x the largest wall
observed); a stage that reaches it is killed with its container and the run
exits 91 without a CSV, since a hung harness is not a measurement. A run that
produced no valid CSV (exit 90, 91, or otherwise) is substituted by the next
number, at most twice per campaign; a third substitution ends the campaign as
invalid. Every discarded run leaves a `runs/discarded_<reason>_run_NN.txt`
sidecar and a line in `runs/execution_order.txt`. Exits 90 and 91 sit outside
the workload's exit-code list.

## Network

Both stages run under `--network none`. Every artifact the jobs fetch is
resolved at image build and verified by sha256: crates, the V8 static library,
the sysroot tarball, the TypeScript compiler package, the harness's esbuild
binary, rustup, Rust and Node.
The test registries the suites use bind loopback ports 4260-4265.
