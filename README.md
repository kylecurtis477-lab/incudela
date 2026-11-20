# Incudela and Cuditor

**Incudela** is an operating system (x86-64 kernel, UEFI loader, drivers, user programs, desktop) and
**Cuditor** is the language it is written in: Python-like syntax, compiled ahead of time to x86-64
assembly by its own assembler and linker, with no libc and no runtime dependencies. The compiler,
`selfhost/cudc.cud`, is written in Cuditor and compiles itself to a fixpoint. Incudela is licensed under
Apache-2.0 and Cuditor under MIT: LICENSE says which applies where, REUSE.toml gives every path its SPDX
identifier, and the texts are LICENSE-APACHE and LICENSE-MIT (also under LICENSES/ for REUSE tools).

## Renamed from Forge

Until 2026-11-16 both were called Forge (repository `kylecurtis477-lab/forge`, now
`kylecurtis477-lab/incudela`; GitHub redirects the old URLs). CHANGELOG entries before the rename keep the
old names as history.

| Before | After |
|---|---|
| Forge (the language), `.forge`, `.fsi` | Cuditor, `.cud`, `.cudi` |
| `forgec`, `seed/forgec-seed`, `./forge` | `cudc`, `seed/cudc-seed`, `./cuditor` |
| `# forge: ...` pragmas, `forge.toml`, `forge.lock` | `# cuditor: ...`, `cuditor.toml`, `cuditor.lock` |
| `FORGEC_FLAGS`, `FORGE_GUID_SEED` | `CUDC_FLAGS`, `INCUDELA_GUID_SEED` |
| forgeseal, forge-part, forge_test, forge_verify, c2forge | cudseal, incudela-part, cud_test, cud_verify, c2cud |
| Forge (the OS), `forge-kernel 0.2.6`, Forge UEFI loader, Forge FS | Incudela, `incudela-kernel 0.2.6`, Incudela UEFI loader, Incudela FS |
| `forge.iommu=`, `forge.desktop` (boot command line) | `incudela.iommu=`, `incudela.desktop` |
| ESP folder `\EFI\Forge\`, loader `forgex64.efi` | `\EFI\Incudela\`, `incudelax64.efi`; old disks keep booting from `\EFI\Forge\` until `tools/espmigrate.cud` moves them ([docs/tools-espmigrate.md](docs/tools-espmigrate.md)) |

Removed in 0.22.0 (read, with a warning, in 0.21.x only): `./forge`, `# forge:` pragmas (and cudseal's
`# forge: caps(...)` lines), imports of `.forge` modules, `forge.toml`/`forge.lock`, `FORGEC_FLAGS`, `FORGE_GUID_SEED`
and the `forge.iommu=`/`forge.desktop` boot command-line keys. They are now ordinary comments, files, variables
and tokens with no effect (tests/oldnames, tests/cudseal). Kept for
good (on-disk and wire formats): the magics `FORGEKRN` (kernel header), `FORGEFS1` (Incudela FS superblock)
and `FORGEPRF` (seal proof slot), the Incudela FS partition type GUID D0C2E3A1-6B7F-4F0A-9E11-466F72676546, the
Linux personality's `uname` strings, and internal symbol names such as `forge_alloc` and `forge_py_*`.

## Status
- **Renamed (2026-11-16):** the language is now **Cuditor**: sources are `.cud` (library includes `.cudi`), the compiler is `cudc` (`seed/cudc-seed`), the driver is `./cuditor`, pragmas are `# cuditor: ...`, packages use `cuditor.toml`/`cuditor.lock`, and the tools are `cudseal`, `incudela-part`, `cud_test`, `cud_verify` and `c2cud`. The old spellings were read for the 0.21.x releases and are gone in 0.22.0 ("Renamed from Forge" above).
- **Self-hosting works.** A checked-in seed compiler (`seed/cudc-seed`), with the seed assembler and linker (`seed/fas-seed`, `seed/fld-seed`; all sha256 pinned in `seed/seed.sha256`), builds stage2 with no GNU as/ld; stage2 builds stage3, and stage3 builds stage4. `stage2.s == stage3.s == stage4.s` byte for byte. Rust is not needed: the old Rust bootstrap (src/main.rs) is only an optional cross-check (`FORGE_RUST_CHECK=1 ./build.sh`). `./cuditor reseed` (tools/reseed.cud; tools/reseed.sh is the reference) refreshes the seed from a green build.
- **Tests:** `./run_tests.sh` runs 36 tests: 23 program tests, 6 runtime-error tests and 7 compile-error tests. All pass. Except for `gc`/`gc_retention` (which use `mark()`/`release()`), the program `.expected` files are CPython output.
- **Plan order:** docs/BUILD_PLAN.md, "Current execution order": (1) a working screen (framebuffer graphics, a desktop shell with a terminal window), (2) ownership-typed struct fields, applied first to kernel data structures, (3) an optimizer correctness gate (coverage, every opt-flag combination fuzzed; done 2026-11-13, new passes land only with `optcov --check` and `fs-opt-combos` green), (4) the SSA backend gated by it, (5) the language server, (6) the package manager (dependency resolution, signed packages, reproducible builds), (7) sustained adversarial testing, (8) real-hardware boot, (9) Linux compatibility measured with real apps, (10) diverse double-compilation of the seed. The v1 reservations mix in at about one commit in five; the other Phase 8 leftovers come last. The never-reboot promise is split into three tiers (service restart, live driver update, live kernel replacement). Items 2-10 and the tiers follow an outside review (ChatGPT, 2026-11-12). Post-1.0 ideas are in the "Version 2" section. docs/kernel-core.md Appendix A lists all 41 OS result names; tests/os/kexec-compat.sh hands over from a kernel built from an older commit (61b3e85) to this tree's kernel. A dated schedule for the remaining items (estimates from the quota-log pace) is in BUILD_PLAN, "Dated schedule (2026-11-15 assessment)".
- **Screen (steps 1-6, build-plan item 1 complete):** boot with `incudela.desktop` on the kernel command line and the kernel draws a desktop through examples/kernel/gfx.cudi (back buffer, rectangles, text at any pixel, damage-based present) with a terminal that opens on the boot log, and a mouse cursor driven by PS/2 mouse and keyboard events (examples/kernel/input.cudi), all shown through a windowed compositor (examples/kernel/wm.cudi: the terminal and two floating windows, z-order, damage repaint, click to focus, title-bar drag) and a window drawn by a sandboxed program that declares only the `gfx` capability (examples/user/gfxapp.cud, kernel side examples/kernel/appwin.cudi); a desktop shell (examples/kernel/panel.cudi) adds a taskbar with a button per window (raise, or minimize the focused one) and a launcher menu that restores and raises any window; tests/os/desktop.sh drives it through QEMU's monitor and checks it from a screendump.
- **Compiler limits:** an fs function may have 4096 locals (counting block names, temporaries and own-field slots); the 4097th is a diagnostic at its line, not an internal index error (tests/limits)
- **Device grants:** a user-mode driver's DMA grant (drv 402) names an address-space ID; only 0 exists today and any other is refused, so per-process IOMMU domains can come later without an ABI change (v1 reservation 3).
- **Ownership (freestanding/kernel code):** `own[T]`, `ref[T]` and `mut[T]` pointers with move and borrow checks (docs/BUILD_PLAN.md Phase 4 item 4, tests/own). Stage 2: direct `own[T]` fields in local structs support definite initialisation, move-out/reinitialisation, lexical per-field borrows and branch/loop move tracking. Structs containing owners cannot be passed or returned by value; nested owner-bearing structs, arrays/slices of owner-bearing structs, and owner-bearing globals remain refused. `ref`/`mut` fields remain refused. Review fixes (separate commits): only the outermost assignment target takes the field-store path (`a[f(q.head)] = v` reads `q.head`; `q.f[i]` and `op=` are borrow-checked place accesses), `addr()` of an own/ref/mut value is an unsafe operation, and hosted code refuses `own[`/`ref[`/`mut[` in every type position. Stage 3a: an `own[T]` field behind a local `own`/`mut`/`ref` pointer is usable as a place (`p.head.id`, written only through `own`/`mut`); moving it out through the pointer waits for `take`/`replace` (Stage 3c); raw `ptr`/`nptr` bases are refused even in unsafe code. (Its comment block was reformatted with `build/fmt` in a separate commit; `fmt --check` is part of the gate.) Arrays and slices of own/ref/mut (`own[T][N]`, `slice[ref[T]]`) are refused in every position, not only as struct fields: `a[0]` copied twice gave two owners. `addr()` of a place reached through a `ref[T]` (`addr(p.id)`, `addr(p[0])`) is an unsafe operation: the raw pointer was writable through a shared borrow. Stage 3b-min: `nown[T]`, an owner that may be none (0), for locals, parameters, returns and struct fields; it is affine like `own[T]`, a null test (`o == 0` / `o != 0`) does not move it, and it is usable as an `own[T]` (field access, `borrow`, passing, returning) only inside `if o != 0:` or after `if o == 0: return`; `own[T]` converts to it by moving, the reverse needs that check. A `nown` field of a local struct starts none and is move-tracked (moved is not none); through a pointer it can only be tested for none (moving or storing waits for `take`/`replace`). `nown` globals and arrays wait for Stage 3c. Two holes fixed in separate commits: pointer arithmetic on own/ref/mut (`q + 8` gave a second owner) and `p[i]` reading or writing an owner through a pointer (`a = q[0]; b = q[0]` on an `own[own[T]]`) are unsafe operations. Stage 3c: `take(place)` (returns the `nown[T]` and leaves the place none), `replace(place, v)` (stores `v`, returns the old owner) and `swap(a, b)` (two provably different places) on named places only: own/nown locals, direct own/nown fields of local structs, and own/nown fields through local `own`/`mut` pointers; never through `ref` or raw pointers, never on temporaries, never while the place or its root is borrowed. They are how owners move into and out of fields behind pointers; user functions with those names keep working. Fix (separate commit): passing a `mut[T]` as an argument while a shared borrow of it is live (`r = borrow(m); bump(m)`, or `both(borrow(m), m)`) is refused; the callee could write what the `ref` still reads as shared, and Stage 3d's pointer-root borrows rely on it. Fix (separate commit, Stage 3c): `swap(a, b)` also refuses two places where one is reached through the other (`swap(x, x.next)`), which stored the old owner into its own child. Stage 3d: `borrow(p.head)`/`borrow_mut(p.head)` through a local `own`/`mut`/`ref` pointer (or a narrowed `nown`, or a local struct's own field) record the borrow on the root `p`, so the root cannot be moved, reassigned, written, passed as `mut` or used by `take`/`replace`/`swap` while it lives (any use at all for `borrow_mut`); nested owner paths (`p.head.next.id`, `borrow(p.head.next)`, `take(p.head.next.slot)`) follow `own` fields only: a `nown` step must be taken into a local and checked first, `borrow_mut` and writes through a `ref` root are refused, and raw roots stay refused even in unsafe code. `nown[T]` globals and global arrays `nown[T][N]`: they start none (zero is none, no initializer), and a global or an element `a[i]` is a place used only by `take`/`replace`/`swap` (any index expression, evaluated once with the usual bounds check) or a test for none (`a[i] == 0`, `g != 0`); plain reads, stores, field access, `addr()` (even in unsafe code), slicing and whole-array use are refused, and there is no narrowing (any call could empty a global). Local, parameter, field and nested arrays of `nown`, and global structs with `nown` fields, stay refused. Stage 3e (kernel): the run queues own their READY threads (`rq_head`, `current`, `idle_thr` are `nown[Thread][8]`, linked through `Thread.rq_next: nown[Thread]`); `rq_pop` is safe code, `schedule_l` has one transfer point (`replace(current[cpu], nxt)`), `thread_adopt` is the only raw-to-owner step and panics on a second owner; kernel unsafe report 168 functions / 701 ops (was 170 / 708). Stage 3f: the kexec handoff records are typed (`struct PsRecord`, `struct KxdRecord`, every offset checked at boot), written through one `own` per record that the sealing function consumes and adopted one owner per record; kernel unsafe report 168 / 659.
- **Recovery:** the source transcript cut every `main.rs` write off at 4101 chars. The lexer and the edit fragments were recovered (see `recovered/`). The parser, codegen and runtime in `src/` were rewritten. `selfhost_start.cud` is the transcript's latest fragment, taken verbatim; it compiles and prints `scan loop fixed`.

## Build
```sh
./build.sh                 # seed compiler -> stage2..stage4, checks fixpoint, installs build/cudc
./cuditor prog.cud -o prog # compile with self-hosted cudc + as + ld
./run_tests.sh             # non-QEMU items in parallel lanes, output in serial order; then tests/os alone
RUN_TESTS_SERIAL=1 ./run_tests.sh  # same items one at a time, streaming (same result lines and counts)
build/kernel-build --release  # release kernel only (build/kernel-release): no hang probe, no KASLR layout lines
bench/run_bench.py         # Forge vs Rust vs CPython (reference; tools/bench.cud is the Forge tracker)
```
run_tests.sh runs its non-QEMU blocks as 62 items in lanes (table `ITEMS`): lane S (everything that builds or reads build/kernel, build/user, build/efi, build/modules, build/fas or the busybox/cpython trees) in the foreground in order, the other lanes (items with their own scratch files; items sharing one share a lane) as background jobs, and tests/bounds (it compares run times) after every lane has finished. Each item's output goes to build/par/NN.log and is printed in item order, so the output is the serial output; a failed item's log is printed in place with a `# t_item (lane L) exited N, log: build/par/NN.log` line, and an item that left no exit status is `FAIL run-tests/t_item`. The QEMU tests (tests/os) start only after all items are done and run alone. `RUN_TESTS_SERIAL=1` runs the items one at a time.

Optional bootstrap: `target/release/cuditor-bootstrap file.cud [-o out] [-S]`, or `-e 'src'`.

## Syntax
```python
# comments; indentation blocks; optional type annotations
class Point:
    x: int
    y: int

def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

def main():
    p = Point(3, 4)
    p.x = p.x + 1
    xs = [1, 2, 3]
    xs[0] = p.x * p.y
    total = 0
    for i in range(3):
        total += xs[i]
    while True:
        total -= 1
        if total < 10:
            break
        elif total % 2 == 0:
            continue
        else:
            pass
    s = concat("fib=", str(fib(20)))
    puts(s)
    if not str_eq(s, "") and char_at(s, 0) == 'f':
        print(total)
    if argc() > 1:
        puts(argv(1))
    write_file("/tmp/x.txt", "data\n")
    puts(read_file("/tmp/x.txt"))
main()
```

- Statements: `def`, `class` (records with field lines), `if/elif/else`, `while`, `for v in range(a[, b])`, `return`, `break`, `continue`, `pass`, `=`, `+=`/`-=` (on plain variables), index and field assignment.
- Expressions: `+ - * / %` (C semantics: `-7 % 3 == -1`), `== != < <= > >=`, `and or not` (short-circuit), unary `-`, calls, `a[i]`, `a.f`, list literals `[..]`, `"strings"` with `\n \t \0 \\ \"`, char literals `'a'` (ints), `True False None` (1/0/0).
- Values are 64-bit words. Strings are NUL-terminated byte pointers. Lists are fixed-size word arrays.
- Builtins: `print(int)`, `puts eputs`, `str(int)`, `chr`, `concat(a,b)`, `join(list,n)`, `len(s)`, `char_at substr(s,i,n) set_byte str_eq`, `list(n) alloc(bytes)`, `read_file write_file`, `argc argv(i)`, `exit(code)`.
- Variables at top level are globals. Inside a `def`, assigning to an existing global name writes the global.

## Implementation
- cudc is a single-pass recursive-descent compiler (~1040 lines). Output lines are collected in a list and joined once at the end, so string building is not quadratic.
- Optimizations:
  - The first 5 params/locals live in callee-saved registers `rbx, r12–r15`.
  - Simple right-hand operands are used directly, without push/pop.
  - Constant folding for small immediates.
  - Comparisons fuse with conditional jumps.
  - `addq`/`subq` with immediates for `+=`/`-=`.
- Runtime (asm): direct syscalls, a mark-sweep garbage-collected heap (see below), and buffered output.

## Phase 2 additions
String `+`/`*`, f-strings, `for x in list/str/dict`, `enumerate`, tuple assign/swap, ternary, comprehensions with filters, `+=` etc. on names/fields/indexes, dicts (open-addressing hash map, insertion-ordered), slices, `split`/`join`/`upper`, `sorted`/`min`/`max`, classes with `__init__` and methods and per-class field layout (dynamic dispatch by name), Python floor `//` and `%`.
Runtime errors carry source lines: index out of range, missing key, division by zero (`tests/runtime`).
Memory: see Phase 3 (GC). `mark()` returns bytes in use; `release(m)` forces a full collection.

## Phase 3 additions
- Values: real `True`/`False` (tagged), `None` as a distinct value that prints `None`, boxed 64-bit floats with Python formatting and mixed arithmetic.
- Classes: single inheritance, `super()`, `isinstance` (`tests/inherit`); exceptions with `try/except/else/finally`, exception classes, `raise`, line-numbered uncaught errors (`tests/exceptions`).
- Functions: `lambda`, nested `def`, closures with `nonlocal`, first-class functions (incl. builtins like `str`/`len` as values), `map`/`filter`, `sorted`/`sort` with `key=`/`reverse=` (`tests/closures`, compared with CPython).
- **Garbage collector:** a non-moving, conservative mark-sweep collector in the hosted runtime, `selfhost/runtime.cud` (naked Forge functions with inline asm; `selfhost/runtime.s` is the original, kept as the byte-check reference).
  - Heap: 64 KiB pages in a 64 GiB reserved region, plus a page table. Small objects use 38 segregated size classes (16 B steps up to 512 B, then powers of two up to 32 KiB) with free lists. Larger objects get page runs (first fit). Free pages and runs are returned to the OS with `madvise(DONTNEED)`.
  - Roots: all registers (spilled at the allocation point), the whole machine stack up to the entry `%rsp` (which also covers the exception-handler frames saved on the stack), every global and data object (`rt_dlo..rt_dhi`), and `rt_exc_val`. Interior pointers are accepted. Strings and floats are not scanned.
  - A collection triggers when the bytes allocated reach `max(32 MB, 2 × live)`.
  - `tests/gc` churns about 1 GB of strings, lists, cyclic objects, floats, closures and exceptions. Its peak RSS is 44 MB with GC versus 819 MB without. The compiler runs with GC on while self-compiling (the fixpoint holds). Its peak is still ~300 MB because most of what it allocates stays live: the emitted assembly lines are kept until the final `join`.
Optimizer: multi-pass int-type inference, magic-number division by constants, top-5 weighted locals/params in callee-saved registers, scratch registers for temporaries, inlining of single-`return` leaf functions, hoisting of invariant safe calls in loops, jump-based conditions and rotated loops, and dead-function pruning.

## Phase 4 additions
- Generators and `yield` (including generator expressions as call arguments), `with` statements and file I/O (`open`, `read`, `write`, `readlines`, iteration).
- Imports of other `.cud` modules (`import m`, `from m import f`) and a small stdlib: `sys.argv`, `sys.exit`, `os` helpers, `time.time`/`perf_counter`.
- Set comprehensions, dict comprehensions and nested comprehensions; real tuples.
- **Bigints:** dynamic (untyped) int arithmetic promotes to arbitrary precision on overflow (`+ - * // % **`, comparisons, hashing, `str`/`repr`, mixing with floats). Int-typed or inferred-int arithmetic in user code raises `OverflowError` instead of wrapping. The checks are a fall-through `jo` to a cold stub at the end of the function. `# cuditor: wrapping-ints` turns them off (the compiler itself uses it).
- Loose ends: keyword arguments and defaults on indirect calls (function values, closures, lambdas), lambda default arguments, `nonlocal` through intermediate scopes, `def` inside top-level `if`/`for`/`while` blocks, `for i in range(...)` leaves `i` at its last value as in Python.
- GC: `pop`, `del`, slice deletion, `clear` and dict deletion clear the vacated slots, and `release()` clears scratch registers first, so dropped objects are no longer retained (`tests/gc_retention`).

## Benchmarks

Best of 5 wall clock. Rust: rustc -C opt-level=3 (unstripped binaries). Phase 1 Forge: fib 0.015s, loop 0.274s, strbuild 0.093s, lists 0.189s. Phase 3: fib 0.015s, loop 0.088s, strbuild 0.090s, lists 0.176s.

| bench | Cuditor run | Rust -O3 run | CPython run | Forge compile | Rust compile | Forge bin | Rust bin | output |
|---|---|---|---|---|---|---|---|---|
| fib | 0.010s | 0.006s | 0.18s | 172ms | 233ms | 137,296 B | 11,395,072 B | 2178309 |
| loop | 0.094s | 0.073s | 5.50s | 203ms | 184ms | 137,264 B | 11,395,024 B | 199999997 |
| strbuild | 0.027s | 0.053s | 0.08s | 275ms | 328ms | 137,344 B | 11,399,736 B | 6888890 |
| lists | 0.042s | 0.045s | 2.96s | 190ms | 223ms | 137,384 B | 11,399,120 B | 49950000000 |
| floats | 0.031s | 0.015s | 0.18s | 237ms | 174ms | 137,776 B | 11,390,192 B | 1500122368 |
| strops | 0.018s | 0.017s | 0.04s | 165ms | 324ms | 138,656 B | 11,516,016 B | 38408 977889 22311 |

(Run 2026-11-01 20:08 CST with the default -O, including the 2**62 band checks; self-compile 1.25s. Full history and -O0 numbers in bench/results.md.)

Performance is tracked by `./cuditor bench run` (tools/bench.cud): each bench against its Rust -O3 reference, plus the
self-compile time, appended to bench/history.tsv under the full commit sha (a tree with uncommitted changes is refused, or recorded marked `+dirty` with `--allow-dirty`). `./cuditor bench check` compares the newest record with
bench/baseline.tsv (fails above +25%) and reports the Phase 12.4 targets. See docs/tools-bench.md.

### Optimizing backend (default; `-O0` turns it off)
(In freestanding mode `-O0` turns off bounds-check elision, the one fs optimization that is on by default; the
opt-in `--fs-opt`/`--fs-live`/`--fs-temps`/`--fs-ssa` passes still run when named. See docs/SYSTEMS.md, "Optimization levels". Reproducibility tests that compare two builds pin the same CUDC_FLAGS for both. The bounds-check overhead test, tests/bounds/run.sh, times 21 pairs of 3 interleaved checked/`--no-bounds` rounds and requires the median of the 21 per-pair ratios (best checked / best unchecked within the pair) to be at most 1.05; comparing the two best runs failed under gate load with identical code in inv138 and inv156.)
Eligible functions are plain int functions with int params. They are lowered to a three-address IR with virtual registers and basic blocks. The passes are const/copy propagation with folding, unreachable-block and jump cleanup, local CSE, liveness-based DCE, and elimination of tag and bounds checks for typed non-escaping `list[int]` locals. Registers are assigned by linear scan over rsi/rdi/r8-r10 and rbx/r12-r15, with spilling. Division by a constant uses magic numbers. Any function that is not eligible uses the direct code generator.

## Systems programming (freestanding mode)
`# cuditor: no-runtime` or `--freestanding` selects a runtime-free backend. It has fixed-width ints, pointers, C-layout and `@packed` structs, inline asm, port I/O, CPU and atomic intrinsics, C and MS x64 ABI extern/export, and interrupt and UEFI entry attributes. Float globals take float literals, stored as IEEE bits (f32 rounded to nearest even at compile time).
It powers `examples/kernel` and `examples/efi`. The kernel is a higher-half x86-64 kernel with a frame allocator, its own 4-level paging, a heap, demand paging, a framebuffer console, ACPI/IOAPIC/LAPIC timer, IST stacks, SMP with a preemptive scheduler, ring-3 Incudela user programs via syscall/sysret, and PCI + virtio-blk + read-only FAT32 (it loads `\EFI\Incudela\init.elf` from the ESP); its NVMe driver takes I/O completions on an MSI-X interrupt and its AHCI driver on an MSI interrupt (sleeping readers), and its e1000 and virtio-net drivers resolve the QEMU gateway by ARP, ping it (ICMP echo) and serve UDP echo on port 7. Its xHCI driver enumerates the first USB device and configures a HID boot keyboard (configuration descriptor walk, SET_CONFIGURATION, SET_PROTOCOL(boot), SET_IDLE), then adds its interrupt IN endpoint (Configure Endpoint, a transfer ring of report TRBs) and decodes the 8-byte boot reports into text; after that the keyboard runs on an MSI-X interrupt and its keys go into the shell's tty input. On Intel VT-d machines it programs every remapping unit with default-deny DMA: only devices the kernel drives and user-mode driver DMA grants get context entries, and an audit checks all 65536 requester IDs. DMA faults are read and reported, and requester-ID aliases behind PCI bridges get entries too. Without a remapping unit the boot log states the permissive DMA policy, and a strict mode refuses driver DMA grants; strict is chosen at boot by a sealed `\EFI\Incudela\boot.cfg` (`cudseal --config`) or by `incudela.iommu=strict` on the command line, which can only tighten (examples/kernel/bootpol.cudi). With interrupt remapping, device MSI/MSI-X messages go through source-validated remapping entries. `examples/efi` is a native UEFI loader written in Cuditor (`\EFI\Incudela\incudelax64.efi`) that loads the kernel from a GPT ESP shared with Windows and Linux. The kernel boots through GRUB on BIOS and UEFI, or through the Forge loader (see docs/SYSTEMS.md).
Both are boot-tested headless in QEMU/OVMF by `tests/os/run.sh` (the boot harness checks the framebuffer only once two consecutive screendumps after `KERNEL OK` decode identically). See docs/SYSTEMS.md for the subset, dual-boot design, and roadmap, and docs/BUILD_PLAN.md for the phased build plan.
`cudc --fs-opt` (Phase 12.1 steps 1–3, 4a) keeps scalar locals in registers (callee-saved ones across calls, and since step 4a also in safe functions with frame arrays, structs or `addr()`), peepholes the stack-machine code and divides by constants with a multiply. The kernel is built with it since step 3 (kernel code 534,272 to 495,157 bytes), after an audit of every hand-written asm routine for SysV register discipline (a checklist in docs/SYSTEMS.md that tests/asm-audit/run.sh keeps complete); the UEFI loader and the kernel modules since step 3b (loader -8.7%, modules -14%); the user programs since step 3c (-4.2%, frame accesses -20%). tools/fsfuzz.cud checks it differentially: random programs built with and without it, at O2 and -O0, must print the same (`fs-opt-fuzz` in run_tests). `cudc --fs-live` (step 4b) adds liveness-based register sharing: slots whose live ranges do not overlap share one register. The kernel is built with it (frame accesses 11,975 to 11,125, text 596,784 to 595,024 bytes). `cudc --fs-temps` (step 4c, opt-in) passes call arguments straight in registers and loads constants without the stack; the kernel is built with it since then (instructions -14.5%, .text 529,365 to 465,056 bytes, `push %rax` 13,117 to 3,912). `cudc --fs-ssa` (step 4d, opt-in, implies `--fs-temps`) builds SSA values for the ten scratch and argument registers and the flags over each function's control-flow graph (phis at labels, checked by a verifier) and uses the use counts to fold a constant loaded into %rcx into the instruction that uses it, `xor %ecx,%ecx; cmp %rcx,%rax` into `test %rax,%rax`, and `setCC; movzbl; test; je/jne` into one conditional jump; on the kernel instructions 134,600 to 120,544 (-10.4%). The kernel and kernel-next are built with it since the step 4d kernel switch (.text 508,896 to 457,536 bytes, -10.1%; the QEMU boot suite at O2 and O0 is the test). Step 4e, also under `--fs-ssa`, deletes register writes that nothing reads (kernel instructions 120,544 to 119,967), and step 4f propagates register copies (`mov %rA,%rB` chains) into their uses (to 118,980); step 4h tracks the callee-saved registers too, so their copies propagate (to 117,427), and step 4i lets a move whose only reader is the next line's copy write the copy's register (to 115,086); step 4j does the same for a value computed over a straight-line range before its copy (to 112,737), and step 4k lets such a range start with `xor %eA,%eA` (to 112,268; temporaries crossing a label, the planned step 4k, turned out not to occur in this code generator); step 4l keeps straight-line `push`/`pop` round-trips of nested operands in a free register (to 109,854, pops 3,365 to 1,349); since the rounds got cheaper a function gets eight of them instead of four (to 108,520, compile 2.4 s); step 4m lets a call read %rax only as the vector count of a variadic callee, so argument set-ups like `lea s(%rip),%rax; mov %rax,%rdi` load %rdi directly (to 103,596, register moves 17,583 to 12,656); step 4n propagates copies into the base and index registers of memory operands and into the value a store writes (to 102,244, moves 11,296). A fix to the SSA form gives a position with one predecessor its predecessor's values instead of a phi of its own, so copies inside loops propagate too (to 101,399, moves 10,447). Step 4o lets those push/pop round-trips cross a bounds check's failure path, which never comes back (to 99,001, pops 1,058 to 459). Cheaper rounds then brought the kernel's `--fs-ssa` compile from 3.1 s back to 2.3 s, with identical output. Step 4p lets a copy into %rax that feeds an `add`, an `imul` by a constant or a `push` go away (`lea`, three-operand `imul`, `push %rS`), with twelve rounds per function instead of eight (to 97,286, copies into %rax 2,276 to 1,360). Step 4q keeps push/pop round-trips that cross a call in a callee-saved register when the call needs only an alignment pad, and folds unread-high-half `mul` by a constant into three-operand `imul` (to 96,843, pops 410, copies into %rax 1,185). Since step 4g the UEFI loader, the kernel modules and the user programs are built with `--fs-ssa` too (instructions -26%, -21% and -25%). tools/fsfuzz.cud and `optcov --check` gate it (docs/tools-optcov.md, "Landing rule").
The kernel unsafe ceiling in `tests/unsafe/baseline.txt` is 168 functions, 0 blocks, 659 ops, 7 top-level asm blocks (`cudc --unsafe-report` on `examples/kernel/kernel.cud`); the test uses `-le`, so counts may shrink and must not rise. `run_tests.sh` fails closed on the OS tests: without qemu-system-x86_64 and grub-mkrescue it reports `FAIL tests/os`; only an explicit `SKIP_OS=1` skips them, and that run is marked as not a gate pass. Its result names carry the directory (`unsafe-baseline-kernel/kernel.cud`, `unsafe-prov-modules/hello.cud`), since two programs share the file name hello.cud.

Subsystem docs (design, formats, APIs, tests, limits):

- CHANGELOG.md: release notes from 0.17.1 on (0.17.2, 0.17.3 security/VT-d, 0.17.4 fixes, 0.18.0, 0.18.1 cut, open 0.19.0 and 0.20.0, 0.20.1, 0.21.0, 0.21.1, and 0.22.0 closed on 2026-11-19), each entry naming its commit; no tags. The package index will record a signed publish time and a yank flag per version from its first format (BUILD_PLAN item 6)
- docs/process.md: processes, the ELF loader, fork/exec/brk/mmap
- docs/bootstrap.md: the seed compiler, the self-hosting fixpoint and reseeding
- docs/objstore.md: the living object store (Phase 9): versions, blobs, the write-ahead log, persistence, indexes, system rewind and the /obj files-as-objects VFS view
- docs/privacy.md: privacy by design (Phase 10): per-user keys and the object store encrypted at rest; the per-app grant ledger with live revocation (`grants`, `revoke app`); the audit log of every grant event (`audit`)
- docs/linux-compat.md: the Linux syscall personality (Phase 11.1): sealed Linux-ABI images run only in the compat sandbox (`run app`), with the System V start stack and a Linux syscall subset; `lxtest` (raw syscalls, TLS) `lxthreads` (clone threads, futex, group exit) `lxfs` (openat, fstat, getdents64 over granted handles), `lxexec` (execve / execveat inside the sandbox) and `lxsig` (signals: handlers, masks, kill/tgkill of itself, SIGSEGV on a fault, resumed with every register restored: rt_sigreturn leaves by iretq) are the self-built test programs; BusyBox 1.38.0, built from verified source against musl (`tools/busybox/build.sh`, foreign seal level 3), is the acceptance test (`run busybox`); syscalls added for it one per commit: geteuid 107, dup2 33, lseek 8, ppoll 271. Phase 11.1 is accepted: BusyBox ash runs a script (`busybox sh /efi/incudela/docs/hello.sh`) in the sandbox; external commands and pipelines in ash need fork, not supported yet. Phase 11.2 (C FFI) is complete: SysV stack arguments (more than 6 words, both directions; tests/fs/cabi8), structs by value and struct returns (rax:rdx, hidden pointer over 16 bytes; tests/fs/cabi_struct), f64/f32 floats in xmm registers (tests/fs/cabi_float), structs with float fields by value (SysV eightbyte classes SSE/INTEGER, xmm + gpr, returns in xmm0/xmm1/rax/rdx; tests/fs/cabi_floatstruct); plan v1.3 provenance rule: integer-to-pointer only in @unsafe functions, checked by `cudc --provenance-lint`, pointers to C keep provenance; seal v3 trailers (version, algorithm IDs, up to 3 signatures, reserved proof slot; Ed25519 only, v2 still accepted); C-to-Forge (tools/c2cud.cud, planned subset steps 1–7 done: lexer through a first real library matching gcc at O2/O0; remaining gaps listed in BUILD_PLAN item 4); Python FFI 11.5(a) done (pinned CPython 3.13.5 built from official source by tools/cpython/build.cud; Forge embed API in tools/cpython/embed.cudi calls libpython through the 11.2 C ABI: Python calls Forge @export functions and Forge calls Python, including a Python function that calls back into Forge, linked with gcc against libpython3.13.a; Python-in-Forge remains a planned track); and all-Forge tooling (the Python tools, runtime.s and the example/BusyBox build scripts ported to Forge; top-level build.sh/run_tests.sh still needs a decision)
- docs/services.md: isolated driver services (kbdd, nvmed) and kexec driver state
- docs/livepatch.md: live patching of kernel functions
- docs/GRAMMAR.md, docs/SYSTEMS.md, docs/BUILD_PLAN.md: the language grammar (v1.2; effect annotations `def f() uses fs, ipc:` are reserved syntax that the checker rejects with E0106), systems features and the plan
- docs/kernel-core.md: kernel core interface spec v1 (scheduler, IPC channels, capabilities), with Appendix A (verification scope: what the tests pin, what they do not, assumptions, the seven DMA/IOMMU gaps, all closed now with their remaining limits, verifier-ready conventions)
- docs/SYSTEMS.md "Process-state format": process-state v2 with a per-record checksum (examples/kernel/pstate.cudi), the single versioned per-process record; the kexec handoff (format v5) carries exactly these
- docs/SYSTEMS.md "Nondeterminism hook": the kernel's single hook point for syscall results, timer interrupts, scheduler choices and random values (examples/kernel/nondet.cudi), recording off by default
- docs/tools-ostools.md: the OS-test toolchain preflight (tools/ostools.cud) the gate runs before any test, and how it reinstalls the tools offline-verified after a box reset
- docs/tools-optcov.md: block coverage of the fs optimizer passes (tools/optcov.cud, build-plan item 3), with the current report and the `-O0` finding
- docs/tools-fsfuzz.md: the `--fs-opt` differential fuzzer (each random program built O2, -O0, --fs-opt, -O0 --fs-opt, --fs-live, -O0 --fs-live, --fs-temps, -O0 --fs-temps, --fs-ssa and -O0 --fs-ssa; outputs must match; `--combos`: 72 flag sets x 2 sources)
- docs/tools-bench.md: the Phase 12.4 performance tracker (bench records, baseline, regression check, targets)
- docs/rfc/incremental.md: RFC (proposed, design only) for a query-based incremental compiler: module/function queries, dependency graph with early cutoff, content-addressed cache, LSP integration, byte-identical output (FIXPOINT, seals unaffected) and the test plan

## Limitations
- Int-typed or inferred-int code raises `OverflowError` rather than promoting to a bigint, e.g. `fact(40)` called with a literal. `int(big)` raises. There are no bitwise operators on bigints.
- No `*args`/`**kwargs`, and `type()` is not supported.
- A module-level `def` name cannot also be rebound as a variable. `class` inside a block is not supported. Two `def`s of the same name in different top-level branches count as duplicates.
- `nonlocal` writes through an intermediate closure only reach the defining scope when that closure has no captured variables of its own.
- The collector is conservative and non-moving, so an integer that looks like a heap pointer, or a stale value in a scratch register at an automatic collection, can keep an object alive.
- Requires binutils `as`/`ld` and Linux x86-64.

## Phase 5

- **Static gradual type checker** (written in Cuditor, runs before codegen). It checks int/float/str/bool/None, list[T], dict[K,V], set[T], tuple[...], Optional[T] / T|None, class types, and Callable, and infers local types. Code without annotations is treated as dynamic. Errors look like `error: line N col M: ...` followed by the source line and a caret. Tests: 15 type-error tests and typed_basics.
- **Optimizer additions:** self tail-call elimination, plus an accumulator transform for `return X + self(...)`. This brings fib from 0.015s to 0.008s. Constant folding, small-function inlining, unboxed typed ints and fixed field offsets were already in place.
- **Still missing:** there is no SSA/linear IR and no linear-scan allocator (locals still go to rbx/r12-r15 first-come). List elements are not typed, so `lists` still uses tag-checked adds and bounds checks. The compiler still uses as/ld; it does not emit ELF itself. Explicit `Base.__init__(self, ...)` calls are not supported, and Optional types are not narrowed by control flow.

Benchmarks (best of 5): see bench/results.md.

## All-Cuditor tooling
- `cuditor provenance [RANGE]` (tools/provenance.cud): every commit since the tool was added carries an AI-provenance trailer (`Provenance:` human, ai-assisted or ai-generated, and `AI-Tool:` for AI-written commits); see docs/PROVENANCE.md.

Policy: every tool that can be written in Cuditor is written in Cuditor (one language to build, debug and troubleshoot). Python tools are ported one per commit and must reproduce the Python original byte-for-byte on representative inputs before any script switches over.

| tool | Forge source | status | verified by |
|---|---|---|---|
| krel (kernel .krel table, KASLR reference) | `tools/krel.cud` | ported; tests/fld uses it; `tools/krel.py` kept as the reference for tests/krel | `tests/krel/run.sh` ([docs/tools-krel.md](docs/tools-krel.md)) |
| incudela-part (create / read the Incudela FS GPT partition) | `tools/incudela-part.cud` | ported; tests/os/forgefs.sh uses it; `tools/incudela-part.py` kept as the reference for tests/incudela-part | `tests/incudela-part/run.sh` ([docs/tools-incudela-part.md](docs/tools-incudela-part.md)) |
| espmigrate (one-time move of an old ESP from `\EFI\Forge\` to `\EFI\Incudela\`) | `tools/espmigrate.cud` | new in Cuditor (no Python original) | `tests/espmigrate/run.sh` ([docs/tools-espmigrate.md](docs/tools-espmigrate.md)) |
| mkgpt (GPT test disk: ESP + Windows/Linux placeholders) | `examples/efi/mkgpt.cud` | ported; examples/efi/build.cud (and the build.sh reference) use it; `mkgpt.py` kept as the reference for tests/mkgpt | `tests/mkgpt/run.sh` ([docs/tools-mkgpt.md](docs/tools-mkgpt.md)) |
| ed25519 (build-time signing: public key / signature) | `tools/ed25519.cud` | ported; `ed25519.py` kept as the reference (cudseal.cud shares its signing code via `tools/ed25519sign.cudi`) | `tests/ed25519-tool/run.sh` ([docs/tools-ed25519.md](docs/tools-ed25519.md)) |
| grammar_fuzz (grammar fuzzer for docs/GRAMMAR.md) | `tools/grammar_fuzz.cud` | ported; tests/grammar/run.sh uses it; `grammar_fuzz.py` kept as the reference | `tests/grammar-fuzz/run.sh` ([docs/tools-grammar_fuzz.md](docs/tools-grammar_fuzz.md)) |
| mkfont (8x16 kernel console font from a TrueType font) | `tools/mkfont.cud` | ported (own TrueType hinter + rasterizer, byte-identical to PIL/FreeType); `mkfont.py` kept as the reference | `tests/mkfont/run.sh` ([docs/tools-mkfont.md](docs/tools-mkfont.md)) |
| cudseal (Seal v3/v2 proof manifests, `--module`, `--foreign`, `--pub`) | `tools/cudseal.cud` | ported; examples/user, examples/modules and tools/busybox build scripts use it; `cudseal.py` kept as the reference | `tests/cudseal/run.sh` ([docs/tools-cudseal.md](docs/tools-cudseal.md)) |
| examples/modules/build.sh (test kernel modules, sealed `--module`, plus negatives) | `examples/modules/build.cud` | ported; examples/kernel/build.sh runs it; `build.sh` kept as the reference | `tests/modules-build/run.sh` |
| examples/user/build.sh (user programs, sealed; seal/ABI negatives; Linux-ABI tests; BusyBox when the source is on the box) | `examples/user/build.cud` | ported; examples/kernel/build.sh runs it; `build.sh` kept as the reference | `tests/user-build/run.sh` |
| tools/busybox/build.sh (BusyBox from pinned source, musl static, EI_OSABI 3, sealed --foreign) | `tools/busybox/build.cud` | ported; examples/user/build.cud runs it; `build.sh` kept as the reference | `tests/busybox-build/run.sh` |
| tools/busybox/bzip2 (stdin/stdout bz2 filter for `tar -xjf` on the BusyBox build PATH) | `tools/busybox/bzip2.cud` | ported; build/busybox-build puts `build/bzip2` on PATH; Python shim kept as the reference | `tests/bzip2/run.sh` |
| examples/efi/build.sh (UEFI loader, FAT32 ESP under \EFI\Incudela\, GPT test disk) | `examples/efi/build.cud` | ported; run_tests.sh and tests/os run it; `build.sh` kept as the reference | `tests/efi-build/run.sh` |
| examples/kernel/build.sh (multiboot2 kernel, kernel-next, GRUB ISO; runs user/modules/BusyBox builds; `--release`: the release kernel) | `examples/kernel/build.cud` | ported; run_tests.sh, tests/os and efi/build.cud run it; `build.sh` kept as the reference | `tests/kernel-build/run.sh`, `tests/kernel-release/run.sh` |
| optcov (fs optimizer block coverage) | `tools/optcov.cud` | written in Cuditor (build-plan item 3) | run_tests.sh `optimizer-coverage` (`--check`: registry of fs options and gated passes, then every never-hit block must be on tools/optcov-allow.txt with a reason) and `optgate*` (tests/optgate); see [docs/tools-optcov.md](docs/tools-optcov.md) |
| ostools (OS-test toolchain preflight: QEMU, GRUB, xorriso, mtools, OVMF) | `tools/ostools.cud` | written in Cuditor (after the 2026-11-13 box reset) | run by the gate harness before every gate, followed by a whole-repo `build/fmt --check` preflight ([docs/tools-ostools.md](docs/tools-ostools.md)) |
| fsfuzz (`--fs-opt` differential fuzzer) | `tools/fsfuzz.cud` | written in Cuditor (Phase 12.1, gate before further step 4 work) | run_tests.sh `fs-opt-fuzz`, seed 1, 20 programs × 10 builds, and `fs-opt-combos`, 3 programs × 144 builds (every optimizer flag combination, `--combos`) ([docs/tools-fsfuzz.md](docs/tools-fsfuzz.md)) |
| forge lsp (language server: diagnostics, definition, hover, references, rename, completion, incremental sync + re-check, UTF-16 positions) | `tools/lsp.cud` | written in Cuditor (Phase 7.5, extended in 11.3) | `tests/lsp/run.sh`, 45 checks ([BUILD_PLAN 7.5](docs/BUILD_PLAN.md)) |
| c2cud (C subset to @unsafe freestanding Forge) | `tools/c2cud.cud` | planned subset (steps 1–7) done; integer/float/array/struct globals (0.15.2); string literals as values; constant-expression global initializers (C `/` and `%`, shifts, bitwise ops); 1-D integer brace lists at file scope and `T a[] = {...}`; tentative and extern redeclarations; float and double globals with initializers; remaining gaps listed in BUILD_PLAN item 4 | `tests/c2cud/run.sh` |
| cpython-build (pinned CPython 3.13.5 from official source; no distro python3-dev) | `tools/cpython/build.cud` | 11.5(a) step 1: pin + install python3, Python.h, libpython3.13.a | `tests/cpython-build/run.sh` |
| cpython-embed (Python↔Forge via 11.2 C ABI; gcc + libpython3.13.a, not fld) | `tools/cpython/embed.cudi`, `tools/cpython/pylayout.cud` → generated `pylayout.cudi` | 11.5(a) done: Forge embed API, Python-to-Forge @export calls and Forge-to-Python eval/object calls; PyConfig/PyStatus/PyMethodDef generated from the pinned headers; non-pinned, free-threaded or debug libpython refused | `tests/cpython-embed/run.sh` |
