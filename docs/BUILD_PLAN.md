# Incudela and Cuditor build plan (named Forge until 2026-11-16)

Release notes per version (0.17.2 on) are in CHANGELOG.md, every commit named (each batch's lines land in the batch after it; complete through 0cd8e2c); versions are commit groupings, not tags. This is the plan to execute, in phase order. It merges the open items from docs/SYSTEMS.md (roadmap items 1–9), the compiler performance list, and six pillars:

- **A. Provable safety.** Forge is memory-safe by default:
  - ownership/borrow or region checking;
  - bounds checks, with elision where they can be proven unnecessary;
  - no null;
  - `unsafe` blocks that are checked.

  The OS uses capabilities, and everything runs sandboxed.
- **B. AI-native.**
  - A tiny, regular grammar.
  - Machine-readable diagnostics and a JSON AST.
  - Built-in test/verify tooling.
  - Later, an OS intent/command layer.
- **C. One language everywhere.**
  - Forge for the kernel, apps, and servers.
  - Generics, slices, a package manager, a stdlib, an LSP, a formatter, and DWARF.
  - Later, ARM64 and GPU backends.
- **D. Instant and seamless.**
  - Fast boot.
  - Reproducible, declarative system configuration.
  - A sandbox per app.
- **E. Auto-parallelism.** SIMD, parallel-for, and a multicore runtime.
- **F. Compatibility.**
  - A Linux syscall ABI layer that runs static Linux ELF binaries.
  - C and Python FFI.
  - Real hardware drivers: NVMe, AHCI, USB/xHCI, e1000/virtio-net, GOP.
  - Our own assembler and linker.

**Invariants for every phase:**

- `./build.sh` prints FIXPOINT OK.
- `./run_tests.sh` and `CUDC_FLAGS=-O0 ./run_tests.sh` both report 0 FAIL. This includes the QEMU boot tests (kernel-wx, kernel-bios, kernel-uefi, efi-loader-gpt).
- Dual-boot rules hold:
  - install only into `\EFI\Incudela\`;
  - GPT only, never taking over a whole disk;
  - the kernel only reads the disk until Phase 8 adds a separate Forge data partition, created only with explicit opt-in.
- Each deliverable is committed as soon as its test passes.

A phase is done when every listed test passes in CI (`run_tests.sh`) on both -O2 and -O0.

## Current execution order (2026-11-12, set by Kyle)

The phase sections below stay the record of what each phase means and what is done; this list is the order work
is taken in now. Batches are 3-4 commits, one item per commit, each with a visual and docs; the kernel unsafe
count stays at or under 709 (the baseline ceiling has been 168 / 659 since Stage 3f).

1. **A working screen first** (Kyle, 2026-11-12: "i want a working screen sooner rather than later"). The Phase 8
   graphics and input items and the start of the Desktop and apps track are pulled forward; every step's visual
   is a real QEMU screendump. Steps, one commit each:
   1. Framebuffer graphics in the kernel: pixel primitives (fill, rectangle, blit, glyph at any pixel) over the
      GOP / multiboot framebuffer that the text console already uses (bochs-display/std VGA in QEMU; virtio-gpu
      later), with a boot self-test that draws a test pattern and checks it from the screendump.
      - *Status: done (2026-11-12).* examples/kernel/gfx.cudi: a back buffer `gfx_buf` (u32, at most 1024x768,
        3 MiB of .bss, bounds-checked) with `gfx_fill` (clipped), `gfx_frame`, `gfx_get`, `gfx_char`/`gfx_text`/
        `gfx_num` (the 8x16 font at any pixel, any fg/bg) and `gfx_present`, which copies the damaged bounding box
        to the framebuffer. Colours are 0xRRGGBB and converted to the framebuffer's byte order on the way out.
        Every framebuffer store, console and desktop, now goes through `fb_px` (console.cudi), one bounds-checked
        store, so the kernel unsafe report fell from 709 ops to 708 (the function count stayed 170: `cudc --unsafe-report` at 1a51b4b). `incudela.desktop` on the
        boot command line skips the shell and kexec sessions, runs `gfx_selftest` (fills, clipping, glyph pixels,
        byte order), draws the desktop (background, 8 colour bars, two text rows, a framed area), presents it and
        sends console text to serial only. tests/os/desktop.sh (GRUB BIOS, about 11 s) reads both rows back from
        the QEMU screendump and checks the 8 bars pixel by pixel. It adds the result os/desktop, so
        os/result-count goes from 38 to 39 results (approved by Kyle, 2026-11-12). The first screendump found the
        multiboot2 byte-order bug (red and blue swapped on GRUB boots), fixed in its own commit.
   2. Text on screen at any position and colour through a proper font path (the 8x16 font in font.cudi), and a
      graphical text console that the terminal window reuses.
      - *Status: done (2026-11-12).* gfx.cudi adds a terminal: a cell grid at any pixel origin with its own
        colours (`term_open`, `term_putc`, `term_newline`), scrolling by moving back-buffer rows (`gfx_scroll`)
        and presenting the damage at each newline. `term_replay` opens it on the text console's last rows (the
        boot log as the console showed it; rows that filled the width are not doubled). Once the desktop is up,
        console.cudi `putc` sends text to serial and the terminal (`gfx_putc`). The desktop now has a title bar
        ("Terminal: kernel console") and a 128x39 terminal; tests/os/desktop.sh reads its last two rows, the
        desktop line and KERNEL OK as whole rows, from the screendump. Unsafe report unchanged (169 / 708).
   3. Input events: PS/2 mouse plus the existing PS/2 and USB HID keyboards feeding one event queue
      (key down/up, mouse move/buttons), visible to user programs through a capability-checked syscall.
      - *Status: kernel side done (2026-11-12); the user-program syscall comes with step 5.* examples/kernel/
        input.cudi: one event queue (256 u64 events: kind, scan code or button mask, signed dx/dy) under its own
        lock, filled from the PS/2 handler; the PS/2 mouse is enabled in desktop mode (`mouse_init`: aux port,
        IRQ 12 on the shared `on_kbd`, defaults + data reporting, ACKs checked), and `on_kbd` sorts controller
        bytes by the status register's aux bit (mouse bytes to `mouse_byte`, which builds 3-byte packets into
        EV_MOVE / EV_BUTTON; scan codes keep their tty/kbdd path and are also queued as EV_KEY). All PS/2 port
        access goes through `ps2_io` (ports 0x60/0x64 only). The desktop draws an arrow cursor over the back
        buffer (saved and restored pixels; lifted while terminal text is drawn) and, in its input window, moves it
        and echoes buttons and keys in the terminal. tests/os/boot.cud: `FORGE_BOOT_INPUT="MARKER|cmd;..."`
        sends QEMU monitor commands once MARKER appears; tests/os/desktop.sh sends `mouse_move 40 30`,
        `mouse_move 24 10`, `mouse_button 1`, `mouse_button 0`, `sendkey a` and checks the cursor at 576,424 for both
        button changes, scan code 1e, 0 dropped, and the terminal's last rows in the screendump (13 s). Kernel unsafe
        report 169 / 708 -> 170 / 708 (ps2_io is the one new @unsafe function; on_kbd's two port reads moved
        into it).
   4. A minimal desktop shell: a windowed compositor (back buffer, window list, z-order, damage-based redraw)
      that draws at least a terminal window, a mouse cursor, and focus that follows clicks.
      **Done (screen step 4):** examples/kernel/wm.cudi. Windows are a list with a z-order; any change marks a
        rectangle and `wm_paint` repaints it from the models under a clip rectangle (new `gfx_clip`, honoured by
        `gfx_fill`/`gfx_char`): desktop background (`desk_bg`), every intersecting window bottom to top, then the
        cursor. The terminal is window 0 (full width, so the harness still reads its rows whole) and repaints
        through `wm_paint` (cells drawn by `term_draw`; scrolls repaint instead of moving pixels, so floating
        windows are never smeared); About and Help float over it. Left press raises and focuses the topmost
        window under the cursor; a press on a floating title bar drags it (clamped to the screen). tests/os/
        desktop.sh: the monitor moves the cursor to About's title bar (under Help), presses, moves 3 x 100 right
        and releases, then sends a key; serial must show `wm: focus About Incudela` and `wm: About Incudela moved to
        400,170`, and the screendump must show About's focused title bar at (410,175), Help's unfocused title bar
        at (384,252) and terminal where About was (13 s). No new unsafe code (kernel unsafe report 170 / 708).
   5. A sandboxed Forge program with manifest capabilities that gets a window (a draw/event capability) and
      draws into it; anything outside its manifest is refused.
      **Done (screen step 5):** a new capability `gfx` (CAPB_GFX = 256; CAPB_ALL 255 -> 511; both cudseals) gates
        sys 431 win_open / 432 win_fill / 433 win_text (examples/kernel/appwin.cudi, wrappers in ulib.cudi). One
        window per program, at most 320 x 160, pixels in a kernel canvas, every call clipped, only the opener may
        draw. examples/user/gfxapp.cud (caps(gfx) only) opens a 300 x 120 window, draws text and 8 colour bars,
        and records in the window that its file open was refused; gfxdeny.cud (caps(fs)) is refused the window.
        The compositor shows the canvas as window 4. tests/os/desktop.sh checks the serial lines (both denials,
        12 draws, foreign handle refused) and two pixels of the canvas in the screendump. tests/user-build counts
        118 artifacts (was 110). No new unsafe code (kernel 170 / 708). Event delivery to apps, more windows per app and a user-space compositor
        are later Desktop-track items.
   6. A desktop shell around the compositor: a taskbar and a launcher, so every window can be found, brought
      forward and minimized with the mouse. This completes build-plan item 1, the working screen.
      **Done (screen step 6, 2026-11-13):** examples/kernel/panel.cudi. A 32-pixel taskbar (Forge button, one button
        per window, the focused one highlighted) and a launcher menu above it, both drawn by `wm_paint` after the
        windows. A press on a window's button raises it, or minimizes it when it is already focused (`wm_hid`);
        a launcher entry restores and raises its window. The terminal shrinks to 128x37 to sit above the bar.
        tests/os/desktop.sh, after the step 4 drag: About's button (About minimized), the Incudela button (launcher
        open, 4 entries), the About Incudela entry (restored, raised, menu closed), Help's button (Help raised);
        serial must show each step and `shell: 1 launches, 1 minimized, 1 restored`, and the screendump must show
        Help's title over About, About's title unfocused, the taskbar, the Incudela button, Help's button focused,
        About's not, and no launcher (21 s). Found while making the visual: a click-raise left the taskbar
        showing the old focus, so `wm_raise` now repaints it. No new unsafe code (kernel 170 / 708).
2. **Ownership-typed struct fields.** `own`/`ref`/`mut` as struct field types, borrow checks through field access,
   and non-lexical borrow ends where the rule is simple. Applied first to kernel data structures: the run queue,
   page tables and the handoff records.
   - *Status: Stage 1 done (2026-11-13; patch designed with ChatGPT, reviewed and extended here).* An `own[T]`
     struct field takes its place in the layout (8 bytes, 8-aligned; tests/own/field_layout.cud asserts
     offsetof 16 and sizeof 24 at run time) but any access to it, read, store or borrow, is a compile error ("own/ref/mut
     field access requires field borrow and move tracking") until Stage 2 adds per-field move and borrow state. Whole
     structs cannot be assigned, so no owner is copied that way. `ref`/`mut` fields stay illegal ("ref/mut struct
     fields need lifetime tracking"), and so do arrays and slices of owners (the separate fix commit before this one).
     5 new tests in tests/own (27 checks): field_layout, bad_field_copy, bad_field_store, bad_field_borrow,
     bad_field_mut. Stage 2 (to be drafted with ChatGPT): one owner per field, moving a field out marks it empty,
     per-field borrows, definite initialisation before a read; kernel data structures convert only after Stage 2.
   - *Status: Stage 2 done (2026-11-13; patch designed by ChatGPT, reviewed, tested adversarially and fixed here,
     /workspace/chatgpt/REVIEW-stage2.md).* Each direct `own[T]` field of a local struct gets its own move state:
     uninitialised until the first store (reads, member access, indexing and borrows of it are refused before),
     live after a store, moved after a whole-value use (`x = q.head`, `f(q.head)`, `return q.head`), and storable
     again only when moved or uninitialised (overwriting a live owner is "would leak"). Borrows are per field:
     `borrow(q.head)` and `borrow_mut(q.tail)` coexist, the usual many-ref-or-one-mut rule holds per field, member
     access is refused while the field is mutably borrowed and member writes while it is shared-borrowed. Field
     states join at `if`/`elif`/`else`, are checked at loop back edges and `continue`, and return to the entry state
     after a loop, so a field set only in one branch or only inside a loop cannot be read afterwards. Structs with
     owner fields cannot be copied, passed or returned by value (no bitwise copy of an owner); nested owner-bearing
     structs, owner-bearing globals and arrays/slices of them, owner fields reached through a pointer, and
     `ref`/`mut` fields stay refused. Hosted code that writes `own`/`ref`/`mut` is a compile error instead of being
     ignored. Still affine, not linear: a dropped owner leaks. Tests: tests/own/fields_ok.cud plus 12 compile-fail
     cases from the patch (field move, branch, loop, leak, uninitialised read, borrow conflicts, by-value, pointer
     access, hosted). Three issues found in review are fixed in the separate commits that follow this one. Next:
     owner fields through `ptr`/`mut` to a struct (Stage 3), which the kernel run queue and page tables need before
     they convert.
     *Fix 1 (2026-11-13):* the assignment-target flag reached the target's own index and call arguments, so
     `a[sink(q.head)] = v` passed a moved owner on and then marked `q.head` live again (use after move, then a
     second move); `q.buf[0] = v` was refused as a leak when live and accepted when moved; compound assignment
     never checked borrows (`q.head.id += 1` under `borrow(q.head)`). Now only the outermost target postfix sees
     the flag, `q.f[i]` is a place access like `q.f.x`, and `op=` checks borrows and refuses an own field as its
     direct target (tests/own: bad_field_lhs_index, bad_field_index_moved, bad_field_compound_borrowed,
     bad_field_compound_owner, fields_place_ok; 45 checks).
     *Fix 2 (2026-11-13; the `addr()` fix is under Phase 4.4 item 4):* the hosted refusal sat in `reg_func`'s parameter loop only, so `-> own[T]` returns,
     annotated `x: ref[T]` locals and globals and generic arguments (`list[mut[T]]`) were still silently ignored;
     the check is now in hosted `parse_type` and covers every type position (a hosted name `own`, `ref` or `mut`
     still works; tests/own/bad_hosted_own_{return,local,generic}.cud; 50 checks).
   - *Status: Stage 3a done (2026-11-13; restricted patch designed by ChatGPT, reviewed and tested adversarially
     here, /workspace/chatgpt/REVIEW-stage3a.md).* A direct `own[T]` field reached through a local `own[S]`,
     `mut[S]` or `ref[S]` pointer can be used as a place: `p.head.id`, `p.head.arr[i]` and `p.head[0].id` read
     (and, through `own`/`mut`, write) the owned node. The owner itself never leaves the slot: a bare `p.head`
     (move, copy, compare, argument, `addr()`) is "cannot move owner through a pointer: use take/replace", any
     write under `p.head` through a `ref[S]` is refused, and raw `ptr[S]`/`nptr[S]` bases are refused even in
     unsafe code (no ownership facts for raw pointers). Why this is sound without per-pointer state: a `mut[S]`/
     `ref[S]`/`own[S]` only comes from `borrow`/`borrow_mut` of an own local, a parameter, or an unsafe
     conversion from a raw pointer; nothing safe can move an owner out through a pointer, so every own field
     behind one stays initialised. The unsafe conversion carries the obligation (documented in SYSTEMS.md) that
     every own field of the pointee is initialised and uniquely owned. Nested owner fields (`p.head.next.id`,
     `w.q.head.id`) and borrowing `p.head` itself stay refused. Tests: ptr_field_place_ok, bad_ptr_field_move,
     bad_ref_field_write; three Stage 2 tests take the raw-pointer message. Found while testing it and fixed in
     separate commits: arrays/slices of owners outside struct fields and `addr()` through a `ref[T]` (Phase 4.4
     item 4), plus the review fixes in the commit after this one.
     *Review fixes (2026-11-13):* the patch dropped the `len(base) > 0` guard, so after any postfix (base "")
     `fs_local("")` resolved to the newest unnamed frame temporary (a struct call result or return slot); no
     program reached a wrong path through it (those temporaries are structs, and the name lookup that follows
     fails), but correctness hung on that accident, so the guard is back. The runtime test built a `mut[Queue]`
     by casting the address of the `head` field (correct only because head sat at offset 0) and printed a fixed
     string; it now makes one `own[Queue]` in unsafe code and does the rest in safe code (borrow_mut, borrow,
     own parameter, `p.head.id`, `p.head.arr[2]`, `p.head[0].arr[3]` at offset 8) and prints only when the
     values add up. The raw-pointer message said "requires explicit unsafe ownership handling" although unsafe
     code is refused too; it now says so. Seven adversarial cases became tests (bad_ptr_field_{ref_index,
     ref_compound,raw_unsafe,nested,shared_write,arg,index1}); tests/own 70 checks.
     *Fix (2026-11-13, found by gate inv152's fmt-repo-clean):* the patch's comment block in `fs_postfix` sat at
     the body's indentation directly under `if ft_isaff(fft[k]):`; `build/fmt` puts a comment directly under a block
     opener at the opener's indentation (66 other places in the compiler do so), so `fmt --check` failed on
     compiler.cud. Reformatted with `build/fmt`; comments only, the kernel assembly is unchanged.
   - *Status: Stage 3b-min done (2026-11-13; designed by ChatGPT, which declined to write the patch; implemented
     and tested adversarially here, /workspace/chatgpt/stage3b).* `nown[T]` is pointer kind `ftsg` 5, one 8-byte
     word, 0 = none, the owning counterpart of `nptr[T]`. Scope: locals, parameters, returns and struct fields
     reached directly or through `own`/`mut`/`ref` pointers; no globals or arrays (refused with a message) and no
     `take`/`replace`/`swap` yet (3c). It is affine exactly like `own[T]` (moves, "would leak", branch joins, loops,
     borrows, `defer`), even when it holds none. Using it as an `own[T]` (field access, indexing, `borrow`,
     passing or returning as `own[T]`) needs the `fsl_nn` proof that `nptr[T]` uses: `if o != 0:`, `o != 0 and
     ...`, `o == 0 or ...`, or `if o == 0: return`; inside it `o` reads as an `own[T]` but the move state stays on
     `o`, so a narrowed `nown` is never copyable. The null test itself (`o == 0` / `o != 0` ending the comparison)
     reads the word without moving `o`; any other use (bare `if o:`, `u64(o)`, a nonzero literal) moves it as
     before. A move ends the proof (any later use is a use after move) and so does an assignment of a value that
     is not proven non-null. `own[T]` to `nown[T]` is an implicit move; `nown[T]` to `own[T]` only by narrowing;
     raw pointers and integers to `nown[T]` are unsafe operations like raw to `own[T]`; `0` is none. A `nown`
     local or field that holds a known none (declared without an initialiser, `= 0`) has move state -2,
     "initialised, none": a store over it does not leak, and it is distinct from moved (reading a moved field is
     an error, reading a none field gives none). A direct `nown` field of a local struct is a Stage 2 slot (the
     struct is zeroed, so it starts none instead of uninitialised); structs holding `nown` fields count as
     owner-bearing (no by-value use, globals, arrays or nesting). Through a pointer, 3a's place rule stays
     `own[T]`-only: a `nown` field can be tested (`p.slot != 0`, also through `ref`) but never moved, stored,
     dereferenced or borrowed. Hosted code refuses `nown[` in every type position, like `own[`. A program global
     named `nown` keeps meaning that global. Kernel and user assembly are byte-identical; unsafe report 708.
     Tests: nown_ok (runtime) and 26 compile-fail cases (25 bad_nown_*, bad_hosted_nown); tests/own 100 checks with
     the two fixes before this commit (Phase 4.4 item 4: pointer arithmetic on own/ref/mut and `p[i]` of an
     owner through a pointer are unsafe operations). Adversarial set: 54 programs (39 must-reject, 15
     must-accept), all as expected.
   - *Status: Stage 3c done (2026-11-13; designed by ChatGPT in its 3b/3c note, which declined to write the patch;
     implemented and tested adversarially here, /workspace/chatgpt/stage3c).* `take(place) -> nown[T]` returns the
     owner and leaves the place none; `replace(place, v)` stores `v` (moved in, converted to the place's type) and
     returns the old owner with the place's type; `swap(a, b)` exchanges two places of one owner type. They are
     built-ins only when the program has no function (or generic function) of that name, so user
     `take`/`replace`/`swap` keep working. The operands are places, parsed by token shape and never through the value
     path, so nothing is copied: an own/nown local (`take(o)`), a direct own/nown field of a local struct (a Stage 2
     slot, `q.slot`), or an own/nown field through a local `own[S]`/`mut[S]` (or narrowed `nown[S]`) pointer
     (`p.slot`, `m.head`). Everything else is refused: a call result, parentheses, an expression, a global, an index
     (`p[0].slot`), a nested path, any path through `ref[S]` (shared borrow), and raw `ptr`/`nptr` bases even in
     unsafe code (like 3a). `take` needs a `nown` place (an `own` place is never empty: use `replace`). The root and
     the slot must not be dead, moved or borrowed (a shared or mutable borrow of the slot, of an own root or of a mut
     root, including a borrow held for the call the intrinsic is an argument of), and a frame slot must be
     initialised (`replace`/`swap` on an uninitialised or moved own field is refused: assign it instead). `replace`
     evaluates `v` first and resolves the place after it, so `replace(o, o)` or `replace(p.slot, f(p))` is a use
     after move. `swap` proves its places distinct syntactically: different root locals never alias (an `own` is
     unique, a `mut` excludes every other use of what it borrows, `ref` roots are refused), and under one root
     different fields are different words; `swap(x, x)` and `swap(p.f, p.f)` are refused. Frame-slot states follow:
     after `take` (or `replace(o, 0)`) the slot is none (-2), after `replace` live, `swap` exchanges them (a pointer
     field's partner becomes live). Non-null proofs end: the intrinsics clear `fsl_nn` of a local they change, the
     loop-entry scan treats `take(o`/`replace(o`/`swap(.., o` as an assignment, and a condition that calls one of
     them narrows nothing (`if o != 0 and drop(take(o)) == 0:` would otherwise prove a none `o` non-null; found by
     the adversarial set before commit). Through `own`/`mut` pointers this closes the 3b-min gap: owners are moved
     out of and stored into pointer fields only by these operations, so an own field behind a pointer is never left
     empty and a nown field holds none or a unique owner (the 3a/3b invariant). Plain `x = p.slot` / `p.slot = v`
     stay refused. Decision on plain reads of a local struct's `nown` field: they stay a tracked move like `own`
     fields and `nown` locals (one rule for every owner), and the use-after-move error for a `nown` local or field
     now names `take(...)`, which leaves it none instead of moved. No runtime checks, no unsafe operations; kernel
     and user assembly byte-identical, unsafe report 708. Not in 3c: `nown` globals and arrays (and so the `rq[i]`
     element places), nested places, borrowing through pointers (3d). Tests: take_ok (locals, Stage 2 fields, through
     `mut` and `own`, field and pointer/local swaps), take_shadow_ok (user functions win) and 33 compile-fail cases
     (bad_take_*, bad_replace_*, bad_swap_*, bad_nown_field_moved_hint); tests/own 151 checks. Adversarial set: 78
     programs (56 must-reject, 22 must-accept), all as expected.
     *Fix (2026-11-13, found while designing 3d):* passing a `mut[T]` local whole as a call argument reborrowed it
     for the call (`fs_tb_push(l, 2)`) without checking for a live shared borrow, so `r: ref[Node] = borrow(m);
     bump(m); peek(r)` and `both(borrow(m), m)` gave a callee write access to what a `ref` still treated as shared
     (writes through `m` itself were already refused by `fs_wstore`). On master this broke the shared-borrow
     guarantee without a dangling pointer; with 3d's borrows of `m.head` it would let the callee `replace` and free a
     node a live `ref` points to. Now `fs_lchk` refuses it. Tests: bad_mut_pass_shared, bad_mut_pass_shared_arg;
     tests/own 153 checks.
     *Fix to 3c (2026-11-13, found while designing 3d):* `swap` proved its places distinct by comparing (kind, root,
     slot, offset), so an own/nown local and a field reached through that same local looked distinct: `swap(x,
     x.next)` (and `swap(p.slot, p)` on a narrowed recursive `nown`) compiled. It loads both, stores `x.next`'s owner
     into `x`, then resolves `x.next` again through the new `x` and stores the old `x` there: a cycle in which one
     node has two owners. Now `fs_plpre` compares the two operands' token paths: same root name and one path a prefix
     of the other is refused ("needs two disjoint places: one is reached through the other"; equal paths keep "both
     name the same one"). Tests: bad_swap_local_child, bad_swap_nown_child; tests/own 155 checks.
     *Status (3d): done (2026-11-13).* Borrows of owner-field paths are recorded on the root local (`fs_rborrow`):
     `borrow(p.head)` / `borrow_mut(p.head.next)` through a local `own`/`mut`/`ref` pointer, a narrowed `nown`, or a
     Stage 2 own field of a local struct (`l.head.next`, recorded on the field slot). The root then takes the
     existing borrow bookkeeping: a shared borrow refuses moving, reassigning, writing through, passing as `mut[T]`
     and `take`/`replace`/`swap` on it; a mutable borrow refuses every use; call-argument borrows end at the call,
     borrow locals at their block. `fs_chain` resolves nested paths for reads/writes, borrows and the place
     intrinsics: every intermediate step must be an `own` field (a `nown` step can be none: take it into a local and
     check it), `borrow_mut` through a `ref` root and writes under a `ref` root are refused, raw `ptr`/`nptr` roots
     stay refused even in unsafe code, and moving or storing a nested owner still needs `take`/`replace`. `swap`
     keeps the prefix rule (`swap(p.head.slot, p.head.next.slot)` is fine, `swap(p.head, p.head.next)` is not).
     Soundness rests on: a returned borrow is refused, different root locals never alias (unique own, exclusive mut),
     and an own field behind an own/mut root is always live (3c invariant), so a borrow of a path cannot outlive or
     be invalidated through its root. Code is plain loads (`mov off(%rax),%rax` / `mov off(%rcx),%rcx` per step); no
     runtime checks, no unsafe operations, kernel and user assembly byte-identical, unsafe report 708. Tests:
     rborrow_ok (borrow locals and call borrows through own/mut/ref roots, two-level chains, nested
     take/replace/swap, a local struct root) and 8 compile-fail cases (bad_rborrow_*); bad_ptr_field_nested now
     checks a write under a ref root. tests/own 164 checks. Adversarial set /workspace/chatgpt/stage3d/adv: 52
     programs (41 must-reject, 11 must-accept), all as expected. Not in 3d: `nown` globals/arrays and element places
     (`rq[i]`), borrows through `[i]`.
     *Status (`nown` globals and arrays): done (2026-11-15).* A global may be `nown[T]` or one array `nown[T][N]`
     (`fs_tglob` lets exactly that type through `ft_elem_aff` at the top of a global declaration; nested arrays,
     pointers to them, locals, parameters, fields and slices stay refused). Zero is none, so no initializer is
     allowed. Such a global and each element `a[i]` are places for `take`/`replace`/`swap` (`fs_plk` 3 and 4): the
     index is any expression, evaluated once through the ordinary bounds-checked element address (`fs_pladdr`, after
     `replace`'s value; for `swap`, a's index before b's), the address is kept in a frame temporary and the exchange
     is plain `mov`s. Everything else is refused: a plain read (`x = rq[0]`, `f(cur)`, `return cur`), a store (`rq[0]
     = v`, `cur = v`, `op=`), field access through the slot (`cur.id`, even after `if cur != 0:`, since a call could
     empty it: take it into a local and check that), `addr()` even in unsafe code, slicing, `for`, and whole-array
     use; a test for none (`== 0` / `!= 0`) is allowed. Globals have no move state: they are always initialised and
     maybe none, and cannot be borrowed. `swap` refuses the same place twice by tokens (`swap(rq[i], rq[i])`);
     `swap(rq[i], rq[j])` is allowed (with i == j at run time both loads precede both stores, so nothing is
     duplicated). This is what 3e needs for `rq_head`/`current` as `nown[Thread][8]`. Not included: global structs
     (or arrays of structs) with `nown` fields, and local `nown` arrays (locals are not proven zeroed). Concurrent
     access (other CPUs, interrupts) stays the kernel's locking duty, as for every global. No unsafe operations,
     kernel and user assembly byte-identical, unsafe report 708. Tests: nown_global_ok (starts none,
     replace/take/swap across elements, arrays and a global, index evaluated once, swap with a local and a field
     through mut[T]) and 11 compile-fail cases (bad_nown_elem_*, bad_nown_global_*, bad_nown_array_*);
     bad_nown_global now checks a plain read. tests/own 176 checks. Adversarial set
     /workspace/chatgpt/stage3-nown-ga/adv: 48 programs (38 must-reject, 10 must-accept), all as expected.
   - *Next Stage 3 steps (from ChatGPT's design note, in order; each its own gated commit):*
     (3b) `nown[T]`, a nullable affine owner: the only owner type allowed in zero-initialised storage (globals,
     arrays, kexec records), with a null check before use; arrays of owners return as arrays of `nown[T]`.
     *3b-min is done (above): locals, parameters, returns, fields. `nown` globals and arrays come with 3c, since
     an element can only be emptied or refilled soundly by `take`/`replace`.*
     (3c) `take(place) -> nown[T]` (returns the old owner and zeroes the slot in one step), `replace(place, v)` and
     `swap(a, b)` on `nown` and `own` places, with place provenance (root local/param, access path, pointer kind) so
     a move through `mut[S]` is legal exactly when the slot never stays empty; through `ref[S]` never. *3c is done
     (above) for named places; element places of `nown` arrays come with `nown` globals/arrays.* *`nown` globals and
     global arrays, with element places, are done (above).*
     (3d) Borrowing `p.head` records the borrow on the pointer root `p` and releases it at the call or block end;
     nested owner fields through pointers (`p.head.next`) follow from provenance. *3d is done (above).* (3e) Run
     queue: one ownership transfer point between the queue and `current[cpu]` (no owning queue entry while a thread
     runs), tail links stay non-owning, and `rq_push(ptr[Thread])`/`rq_pop() -> u64` become `rq_push(own[Thread])`/
     `rq_pop() -> nown[Thread]` in one coordinated API change. (3f) kexec/pstate handoff records: owner-bearing typed
     records proved layout-compatible at every offset across the old and new kernel, adopted once by the receiver and
     released by `kx_release`; no casting the raw region into several owning pointers. The kernel unsafe count stays
     at or under 709 through all of it.
     *Status (3e, run queue): done (2026-11-15).* `rq_head`, `current` and `idle_thr` are `nown[Thread][8]`; the
     queue is linked through a new owning field `Thread.rq_next: nown[Thread]` (wait queues keep the raw `next`),
     `rq_tail` stays a non-owning `u64` view. `rq_push(own[Thread])`, `rq_pop(cpu) -> nown[Thread]` (safe code:
     `rq_take_first` takes the chain off `rq_head[q]`, re-links the threads it skips in order and hands back the
     first that may run on `cpu`; same placement, pinning, stealing and counters as before) and one owning append,
     `rq_link`, whose mut[Thread] to the tail is the only unsafe step (the tail is owned by the chain, rq_lock held).
     Owners are made only by `thread_adopt` (raw handle -> own; `Thread.rq_owned` makes a second adoption panic):
     `thread_start_ready`, `wake_l`, `sched_cpu_init` and the Linux clone path. `schedule_l` keeps cur's owner in
     `current[cpu]` until the one transfer point `old = replace(current[cpu], nxt)`, then returns `old` to the run
     queue (running), to `idle_thr` (idle) or gives it up (blocked: the wait queue's raw link until `wake_l`; dead:
     `thread_reap`'s handle). `cur_thread()` is a take/replace view of `current[cpu]`; mutex owners compare
     `u64(cur_thread())`. No compiler change. Kernel unsafe report 170 functions / 708 ops -> 168 / 701 (rq_push 1
     -> 0, rq_pop 4 -> 0, schedule_l 4 -> 1, wq_block_l and sleep_ticks 1 -> 0 and no longer @unsafe; new
     thread_adopt 1, rq_link 2); tests/unsafe/baseline.txt ratcheted to 168 / 701. Model test tests/own/runqueue_ok
     (FIFO, pinned skips, stealing, the tail view, current[] views); tests/own 177 checks.
     *Status (3f, handoff records): done (2026-11-15).* `struct PsRecord` (pstate.cudi) and `struct KxdRecord`
     (kexec.cudi, from header +1016) give the process-state v2 record and the driver-state record fields at exactly
     the documented offsets; `ps_selftest` panics at boot unless every `offsetof` and `sizeof` matches
     (`ps_layout_ok`, `kxd_layout_ok`), so handoff format v5 and process-state v2 stay byte-identical. The writer
     turns the zeroed record page into an `own[PsRecord]` once, fills it through field stores (the syscall frame
     word by word from the caller's frame or the parked thread's kernel stack) and `ps_seal` consumes it (header
     word and checksum last); the receiver takes one owner per record, `ps_check` (version, then checksum, same
     panics), reads it through field loads and gives it back with `ps_done` before `kx_release` (the handed-over
     pids are kept in `oldp[]`, so nothing reads a record afterwards). `kxd_save`/`kxd_adopt` do the same with
     `kxd_seal`/`kxd_done` on every path. The FPU page and the page index stay raw. Record order, header and
     checksum checks, panics and boot-log lines are unchanged. Kernel unsafe report 168 / 701 -> 168 / 659
     (sys_kexec 65 -> 58, kx_restore 56 -> 41, kxd_save 13 -> 3, kxd_adopt 12 -> 2); baseline ratcheted. In the gate
     both kexec kernels are built from the same tree; the layout checks are what hold the format to older builds.
   - *Gate infrastructure (2026-11-13):* a box reset removed the QEMU/GRUB/xorriso/OVMF packages and failed a
     gate on setup, not code. tools/ostools.cud now checks the OS-test toolchain and reinstalls what is missing
     (signed Debian index and .debs fetched with curl, installed by apt offline); the gate harness runs it after
     the build and stops with PREFLIGHT FAIL instead of running the tests without their tools
     (docs/tools-ostools.md).
     *Fmt preflight (2026-11-13):* gate inv152 ran its full hour and failed only on fmt-repo-clean (a comment
     block indented against the formatter). The harness now runs `build/fmt --check` over every repo file right
     after the toolchain preflight and stops with `FMT PREFLIGHT FAIL` (listing the files) before any test runs;
     the same check is run by hand before a batch is handed to the gate.
3. **Optimizer correctness gate.** Measure the compiler's test coverage, extend the differential fuzzer
   (tools/fsfuzz.cud) to every combination of optimizer flags, and require it to pass before any new optimizer
   pass lands.
   - *Status (a), coverage: done (2026-11-13).* tools/optcov.cud instruments the fs optimizer functions of
     selfhost/cudc.cud (one counter per block: function body and every if/elif/else/while/for body), builds
     that compiler (its assembly is byte-identical to build/cudc's), compiles the corpus (78 freestanding programs
     from tests/ and examples/ plus 20 fsfuzz programs) under default, --fs-opt, --fs-live, --fs-temps and
     --no-bounds, and reports per pass group: allocator 107/125 blocks, peepholes 8/8, liveness 63/68, temps 49/57,
     constant division 19/20, bounds-check elision 6/6; 252/284 (88.7%) overall, with every block never hit listed
     (docs/tools-optcov.md, mostly defensive bail-outs). Finding: `-O0` changes nothing in freestanding mode (the fs
     backend ignores opt_on), so half of fsfuzz's eight builds were duplicates and the O0 test pass does not run a
     different code generator for kernel and user code. run_tests.sh `optimizer-coverage` runs the quick form.
   - *Status (b), every flag combination: done (2026-11-13).* `fsfuzz --combos` builds each random program under
     all 56 combinations of the optimizer level (7 spellings, redundant ones included), -O0, --no-bounds and -g,
     from the plain source and a stack-protector variant (112 builds), runs every distinct assembly and requires
     identical output. Seeds 1-3 x 25 programs: no miscompile found. A planted miscompile is caught. run_tests.sh
     `fs-opt-combos` runs 2 programs (224 builds). Next for item 3: the rule that a new optimizer pass lands only
     with both checks green.
   - *Status (c), never-hit blocks: done (2026-11-13).* Of optcov's 32 never-hit blocks, the 2 reachable ones (the
     4096-entry pin table of the --fs-opt allocator) are covered by tests/optgate/pins.cud, which run_tests.sh
     also runs under every level (`optgate*`). The other 30 are listed with reasons in tools/optcov-allow.txt (29
     defensive re-checks of code-generator output, 1 capacity limit). `optcov --check` fails on any never-hit block
     not on the list and on any stale entry; run_tests.sh `optimizer-coverage` now runs it (254/284 blocks hit, the
     rest allowed). Finding: more than 4096 locals in one freestanding function crash the compiler instead of
     giving a diagnostic (fsl_* tables); fix queued for the next batch.
   - *Status (d), landing rule: done (2026-11-13); item 3 done.* A new or changed fs optimizer pass lands only with
     `optcov --check` and `fs-opt-combos` green in the same gated batch, its new flag in fsfuzz's flag sets and a
     recorded `fsfuzz --combos` run of at least 25 programs (docs/tools-optcov.md, "Landing rule"). `optcov
     --registry` (run by `--check`) enforces the parts a script can: every `--fs-*` option the compiler parses is
     in optcov's configurations and in tools/fsfuzz.cud, and every fs_* function called under a pass switch
     (fs_ra, fs_live, fs_temps) is in an optcov pass group. run_tests.sh `fs-opt-combos` now runs 3 programs
     (336 builds). Item 4 (SSA backend) is gated by this rule.
   - *-O0 in freestanding mode: done (2026-11-13).* `-O0` now turns off bounds-check elision (constant indices and
     fs_bsafe loop facts; the compile-time error for an out-of-range constant index stays), the only fs
     optimization on by default, so the O0 gate pass builds kernel, EFI loader, modules and user programs with
     every bounds check kept (kernel: 2080 sites, 2080 checked at -O0 vs 1496 at the default; 160,037 vs 153,896
     asm lines). The opt-in `--fs-*` passes stay on when named (the kernel build names `--fs-temps`, since step 4d `--fs-ssa`), so -O0 does
     not turn the regalloc shape checks into failures. Default-level output is byte-identical (kernel checked).
     The -O0 kernel was boot-checked with `CUDC_FLAGS=-O0 tests/os/run.sh` outside the gate. optcov GATES gained
     `fs_elide`. Its first gate (inv149) failed one O0 check, efi-build/esp-reproducible: the test compared a
     `CUDC_FLAGS=""` build with one that inherited -O0 (fixed in the next commit, the test pins the flags).
   - *O0 kernel without `--fs-ssa`: done (inv233).* The kernel build put `--fs-ssa` before `$CUDC_FLAGS`, so the O0
     gate pass (and CI's boot-o0 job) booted `--fs-ssa -O0` code: bounds checks kept, but the SSA backend still on,
     and the plain freestanding code generator never ran on the kernel in any gate. examples/kernel/build.cud
     (`kflags`) and build.sh now drop the default `--fs-ssa` when `$CUDC_FLAGS` has `-O0` (kernel, kernel-next and
     the release kernel); an explicit `--fs-*` in `$CUDC_FLAGS` still applies. kernel-build/O0-no-fs-ssa checks
     that the O0 build's kernel.s is exactly `cudc -O0` output for both the script and the Cuditor build (fails
     on the old flags). Kernel at -O0: 2275 bounds sites, all checked (1667 by default).
   - *`-g` leaves `--fs-*` code unchanged: done (inv234).* dwarf/image-unchanged-by-g could not fail: memimg prints
     `SAME` or `DIFF` and always exits 0, and the test read only the exit status. It now requires the `SAME` line
     (and builds its `-g` kernel with build/kernel's flags, at O0 too); on the old compiler it FAILs, the `--fs-ssa`
     -g kernel's text being 0x5c185 bytes against 0x5c075. Cause: the `.Lfsd<n>:` / `.Lfsde<k>:` line markers were
     in out[] while fs_regalloc ran the passes, which end windows and SSA blocks at labels. fs_dhide / fs_dshow take
     a function's markers out around the passes and put them back in their slots. The -g text (markers, `.loc` and
     debug sections stripped) equals the non-g text for the kernel under every `--fs-*` flag, -O0 and the default,
     and for all 24 tests/fs programs under the four `--fs-*` flags; non-g output is byte-identical.
   - *Fix (2026-11-13, found while filling the pin table for part c):* more than 4096 locals in one fs function
     (every name of every block, frame temporaries and own-field slots count; none is reused) crashed the compiler
     with its own internal error, "error: line 16339: list assignment index 4096 out of range" (a compiler source
     line, not the user's). `fs_newlocal` now stops at FSLMAX = 4096 with "too many locals in one function (limit
     4096, ...): split the function" at the offending line, also for own-field slots. The fsx table (step 4a) was
     already capped safely: a local missing from it is simply not promoted. tests/limits/run.sh (in run_tests.sh)
     generates the cases: 4096 locals build and run, the 4097th and an own-field slot past the limit get the
     diagnostic (on 1d4e26e both crashed).
4. **SSA backend (12.1 step 4), gated by item 3**: a real SSA IR for fs/kernel mode with liveness-based register
   allocation (Phase 12 item 1), in safe steps that are byte-identical for code built without the new flag.
   Steps 4b (`--fs-live`) and 4c (`--fs-temps`) are done and the kernel is built with both. Step 4d
   (`--fs-ssa`, 2026-11-16, opt-in): SSA values over the control-flow graph for the scratch registers and the
   flags, with a verifier, and three use-count folds; the first pass landed under item 3's rule. The kernel is
   built with it since the step 4d kernel switch (2026-11-16). Step 4e (2026-11-16, under `--fs-ssa`) starts
   the SSA-based clean-up of the remaining temporaries: register writes no instruction reads are removed. Step 4f (2026-11-16, under
   `--fs-ssa`): copy propagation through the `mov %rA,%rB` chains between tracked registers. Since step 4g
   (2026-11-16) the loader, modules and user programs are built with `--fs-ssa` too. Step 4h (2026-11-16,
   under `--fs-ssa`): the callee-saved registers (%rbx, %r12-%r15) are tracked in the SSA form, so their
   copies propagate too (`mov %rbx,%rax` in the kernel 2,415 to 1,957). Step 4i (2026-11-16, under
   `--fs-ssa`) starts the SSA-based allocation of the temporaries: a move into %rA whose only reader is the
   `mov %rA,%rB` right after it writes %rB itself. Step 4j (2026-11-16, under `--fs-ssa`) extends that to
   a straight-line range: a value computed in %rax over several lines and then copied out is computed in the
   copy's register throughout. Step 4k (2026-11-16, under `--fs-ssa`): temporaries whose range crosses a label
   do not occur in this code generator (measured: none on the kernel or 63 other sources), so the step instead
   lets a range start with `xor %eA,%eA`. Step 4l (2026-11-17, under `--fs-ssa`): a straight-line `push`/`pop`
   round-trip of a nested operand keeps the value in a free register instead (kernel pops 3,365 to 1,349). Since
   2026-11-17 each round is cheaper (the kernel compiles in 1.74 s instead of 2.31 s, identical output), and a
   function gets eight rounds instead of four (kernel 109,854 to 108,520 instructions, compile 2.36 s). Measured
   (2026-11-17): of the kernel's 17,583 register moves, 5,138 set up a call argument through %rax, the largest
   group, against 1,049 pops in all. Step 4m (2026-11-17, under `--fs-ssa`): a call reads %rax only as the
   vector count of a variadic callee (an argument in %xmm), so those set-ups load the argument register
   directly (kernel 108,520 to 103,596 instructions, moves 17,583 to 12,656). Step 4n (2026-11-17, under
   `--fs-ssa`): copy propagation reaches memory operands (base and index registers) and the register a store
   writes (to 102,244, moves 11,296). Measured again on that compiler (2026-11-17): 1,056 pops, 680 of them
   kept on the stack only because a bounds check's failure path sits between the push and the pop, and 2,782
   copies into %rax, many of them loop counters copied for a compare that copy propagation should already have
   taken. The cause of the second was a bug in the SSA form (fix below: 101,399 instructions, moves 10,447).
   Step 4o (2026-11-17, under `--fs-ssa`): the step 4l round-trips cross a failure path (to 99,001, pops 459).
   Since 2026-11-17 the rounds are cheaper again (the kernel compiles in 2.3 s instead of 3.1 s, identical
   output). Step 4p (2026-11-17, under `--fs-ssa`): of the 2,276 copies into %rax, the largest groups feed an
   `add`, an `imul` by a constant or a `push`, which now take the source register directly (`lea`, three-operand
   `imul`, `push %rS`), and a function gets twelve rounds instead of eight (to 97,286, copies into %rax 1,360).
   Step 4q (2026-11-17, under `--fs-ssa`): push/pop round-trips that cross a call keep the value in a
   callee-saved register when the call's set-up is only an alignment pad (and the pad goes too); unsigned
   `mul` by a constant whose high half is unread becomes three-operand `imul` (to 96,843, pops 410, copies into
   %rax 1,185). A fix: `mul` no longer reads %rdx.
   Step 4r (2026-11-17, under `--fs-ssa`): `mov $N,%rcx; sh* %cl,%rax` becomes `sh* $N,%rax` when that %rcx
   is read once and N is in 0..63 (to 96,232, copies into %rax 1,072).
   Step 4s (2026-11-17, under `--fs-ssa`): `and`/`or`/`xor` into %rax whose flags only feed a following
   `test %rax,%rax` drops the test (to 96,055).
   Step 4t (2026-11-17, under `--fs-ssa`): remaining `mov $N,%rcx; sar|shr|shl %cl,%rax` fold when a later
   call only falsely counts as reading %rcx (`fs_ssa_rcx_lo`); `mov %rS,%rax; sub $N,%rax` becomes
   `lea -N(%rS),%rax` when the flags are unread (N not the int32 min). Kernel instructions 96,055 to 95,918.
   Step 4u (2026-11-17, under `--fs-ssa`): the same rcx_lo check folds `mov $N,%rcx; alu/cmp %rcx,%rax`
   when cnt>1 from a later call. Kernel instructions 95,918 to 95,191.
   Step 4v (2026-11-18, under `--fs-ssa`): `mov $N,%rcx; mul %rcx` / `imul %rcx,%rax` with the multiplicand
   already in %rax becomes `imul $N,%rax` when the high half is unread. Kernel instructions 95,191 to 94,742.
   Step 4w (2026-11-18, under `--fs-ssa`): `and $N,%rax` whose value only feeds setcc becomes `test $N,%rax`
   (same flags; %rax kept so a prior copy can die). Kernel instructions 94,742 to 94,731.
   Step 4x (2026-11-18, under `--fs-ssa`): `setCC; movzbl; test; je|jne L` becomes one `jCC` when L does not
   consume flags and neither edge reads the 0/1 (short-circuit and/or merges keep setne at L). Kernel
   instructions 94,731 to 93,932.
   Step 4y/4z (2026-11-18, under `--fs-ssa`): drop store-then-reload of the same register from the same
   `%rbp` slot, and drop `add $0,%rsp` after calls. Kernel instructions 93,932 to 93,068.
   Step 4aa/4ab (2026-11-18, under `--fs-ssa`): fold `xor`/`mov $N,%rax` through a one-use `%rax` into
   `movq $N,MEM` or `mov $N,%rD`, and retarget `lea`/`mov MEM,%rax` copies into `%rD`. Kernel
   instructions 93,068 to 92,421.
   Step 4ac/4ad (2026-11-18, under `--fs-ssa`): retarget `imul $N,%rS,%rax` (and two-operand `imul $N,%rax`)
   into `%rD`, fold unread-flag `add`/`sub` through `%rax` into `lea` into `%rD`, and store `%rS` straight
   to MEM. Kernel instructions 92,421 to 91,805.
   Step 4af (2026-11-19, under `--fs-ssa`): lines straight after an unconditional `jmp`, with no label between,
   are never run and are deleted. Kernel instructions 90,924 to 89,193.
   Step 4ag (2026-11-19, under `--fs-ssa`): a `jmp .LFk` with `.LFk:` among the labels straight after it is
   deleted. Kernel instructions 89,193 to 87,642.
   Step 4ah (2026-11-19, under `--fs-ssa`): `imul $S,%rR,%rR` (S 1, 2, 4 or 8) read once by the `add` that
   forms an address becomes that address's scaled index `(%rB,%rR,S)`. Kernel instructions 87,642 to 86,168.
   Step 4ai (2026-11-19, under `--fs-ssa`): `lea ADDR,%rT` read once, by the next `mov*` as its memory operand
   `(%rT)`, is folded into that mov (`mov (%rB,%rI,8),%rD`, `mov %rS,N(%rB)`). Kernel instructions 86,168 to 84,336.
   Step 4aj (2026-11-19, under `--fs-ssa`): `ud2` ends a path in the SSA form (it never falls through), so a
   bounds check's pass label keeps the index register and the `%rcx` copy goes. Kernel instructions 84,336 to 83,521.
   Step 4ak (2026-11-19, under `--fs-ssa`): a constant index (`mov $N,%rR`, `xor %eR,%eR`) read once by a scaled
   address goes into its displacement (`mov %rS,24(%rB)`). Kernel instructions 83,521 to 83,106.
5. **The Cuditor language server in Forge**: extend `cuditor lsp` (tools/lsp.cud; Phase 11 item 3): incremental
   checks of changed files, diagnostics, go-to-definition.
   - *Status, batch 1 of 3: done (2026-11-23, 0.23.0, inv218).* Freestanding sources through `include`: a name
     not defined in the file resolves to the top-level defs, structs, `extern def`s and globals of its includes
     (transitively), and for a `.cudi` also of the `.cud` next to it that includes it (its root) and the root's
     includes; hover shows the header (one line for `extern def`) and the file:line. A `.cudi` is checked through
     its root: the include chain is written as hidden siblings that point at each other (all removed afterwards),
     so the root compiles the unsaved buffer. cudc's `NAME.cudi: message` errors go to that file without the
     prefix; a file further up gets one diagnostic on its `include` line (`in util.cudi line 6: ...`); a missing
     include (cudc gives line 0) goes on the line that names it. Saving rechecks the open includers, the root and
     its other open `.cudi`s; included files are parsed once per on-disk text (`forge/stats` reports `parses`).
     Checked by hand on the kernel: hover on `fpu_area_new` in sched.cudi shows cpux.cudi:136, a misspelt call in
     the unsaved buffer is reported on its line through kernel.cud (about 1.7 s for the session). Tests:
     tests/lsp/fsproj and 25 `lsp/fs-*` checks (client.cud `fs` mode; 70 in tests/lsp/run.sh). Next: incremental
     checks (skip the root compile when only a comment or blank line changed, and cache per include), then
     references/rename/completion through includes and struct fields.
   - *Status, batch 2 of 3: done (2026-11-23, 0.23.0, inv219).* Incremental checks: every edit is parsed again
     (syntax errors and a fresh tree for definitions), but the full compile is skipped when the document's code
     lines (not blank, not a whole-line comment) and every file the compile reaches are unchanged since the last
     full compile; that compile's diagnostics move to the new line numbers. The key holds each reached file
     (include closure; for a .cudi its root and the root's includes; hosted imports) both as the open buffer and
     on disk, because a root compiles its includes from disk while a .cudi's chain comes from the buffers (a
     first version keyed on the buffer only kept a stale result when a saved include changed on disk; the test
     fs-include-change-not-reused covers it). `forge/stats` reports `reused`. On the kernel (sched.cudi): about
     90 ms per comment-only edit against about 290 ms per code edit. Tests: 7 more lsp/fs-* checks (77 in
     tests/lsp/run.sh). Next (batch 3): references, rename and completion through includes, and struct fields.
   - *Status, batch 3 of 3: done (2026-11-23, 0.23.0, inv220); item 5 done.* References and rename take in the
     .cudi files next to a document as well as the .cud files (each occurrence still kept only if it resolves to
     the same definition), completion offers the top-level names of the includes (defs, `extern def`s, structs,
     globals), and `p.f` resolves to a struct field when `p` is annotated with a struct or `ptr`/`own`/`ref`/
     `mut`/`nown` of one (definition, hover, references, completion after `p.`). A fix found on the way, its own
     commit (4c7daf9): a struct's field names counted as top-level names of the file (scope_defs and all_names
     descended into struct bodies), so a bare `a` could resolve to field `a`. Include closures are memoised per request. On the kernel:
     references of `cur_proc` from sched.cudi find 61 of its 62 textual hits (the other does not resolve to the
     same definition), about 5.2 s for the first request (every include parsed once) and about 0.5 s after that.
     Tests: 10 more lsp/fs-* checks, plus 1 for the fix (88 in tests/lsp/run.sh).
6. **The package manager**: grow `cuditor pkg` (tools/pkg.cud; Phase 7 item 4) with dependency resolution,
   signed packages and reproducible builds.
   - *Index format rule (2026-11-13, from the Forge Strategist roadmap review):* from the very first index
     format, every published version records a publish time covered by the package signature and a yank flag.
     Dependency cooldowns (do not resolve a version younger than N days) and quarantine (yanked versions stay
     downloadable for existing lock files but are never newly selected) then need no format change later;
     Cargo has just stabilised both.
   - *Batch 1 (2026-11-23): signed index with publish time and yank flag — status: done.* `<name>/index` (v1:
     version, publish time, yank flag, package sha256 per line) replaces `<name>/versions`; `<name>/index.sig` is
     an Ed25519 signature over `cuditor-index-v1 ` + sha256(name LF index), so publish times and yank flags are
     signed from this first format. cuditor.toml pins the registry key (`[registry] key`, also in cuditor.lock);
     `lock`/`build` refuse unsigned, edited, wrongly keyed or name-swapped indexes and package files that differ
     from the index hash. `cuditor pkg publish` (immutable versions, monotonic publish times, only the current
     index's key holder appends) and `cuditor pkg yank`. Quarantine as the rule says: yanked versions are never
     newly selected, but still stage, with a warning, for a lock that has them. Signing and verification use the
     tools/ed25519.cud CLI (new `hexpublic`/`hexsign`/`verify`; verify is the kernel's ed25519_verify), built to
     build/edsig on demand. The fixture packages moved to tests/pkg/packages and are published into a temporary
     registry with the committed test-only key tests/pkg/test-key.seed at fixed times. tests/pkg/run.sh 12 to 29
     checks; mutation-checked (dropping the signature check, the yank filter, the name binding, the index-hash
     check or the publish-time order each makes checks fail). Next: dependency cooldowns, then remote fetching.
   - *Batch 2 (2026-11-23): dependency cooldowns — status: done.* No index format change, as the rule intended:
     cuditor.toml `[registry] cooldown_days = "N"` makes `lock` skip versions whose signed publish time is less
     than N days before `--now` (`cuditor pkg lock --now UNIX`, default the current time; age exactly N days is
     allowed), and `cooldown_exempt = ["name", ...]` exempts packages. Existing locks keep building (cooldowns only
     limit new selection, as yanks do) and the lock does not record the time. The resolution error counts the
     matching versions inside the cooldown. tests/pkg/run.sh 29 to 39 checks (younger versions skipped, the exact
     boundary and one second before it, an existing lock unaffected, exempt and partly exempt, a pin inside the
     cooldown reported, malformed cooldown_days (5 forms), cooldown_exempt and --now refused); mutation-checked
     (no cooldown, `>=` at the boundary, ignoring the exemption, hours instead of days). Next: remote fetching.
   - *Batch 3 (2026-11-23): index rollback protection — status: done.* Closes the gap batch 1 listed (a registry
     serving an older, validly signed index). cuditor.lock becomes lock_version 2 and records per package the
     newest publish time and the yanked count of the index it was made from (`index_newest`, `index_yanked`, inside
     the content hash); both only grow, so `build` and a relock refuse an index with a smaller value, naming both
     states. A version 1 lock is refused with a relock hint. Relative to what the project has seen only (no
     protection for a first lock). tests/pkg/run.sh 39 to 46 checks (the recorded state; a newer index locks and
     builds the same binary; a rolled-back index refused by build and by relock, which leaves the lock alone; a
     rolled-back yank caught by the count; a version 1 lock refused); mutation-checked (no yank count, no build
     check, no relock check). Next: remote fetching.
   - *Batch 4 (2026-11-23): vendoring for offline reproducible builds — status: done.* `cuditor pkg vendor [DIR]`
     runs the same lock check as `build` first, then copies only the locked versions plus their full signed
     indexes into a new directory and checks the lock against that copy, so `--registry vendor` builds offline
     with the same binary hash. tests/pkg/run.sh 46 to 52 checks (only locked files copied, indexes identical,
     offline build hash equal, relock from the copy gives the same lock, an existing directory refused, a lock
     that fails its check vendors nothing, a tampered vendored file refused); mutation-checked (no check before
     copying, signatures not copied).
   - *Item 6 status: done (2026-11-23, 4 batches).* Resolution, signed index with publish time and yank flag
     (quarantine), cooldowns, rollback protection and vendored reproducible builds. Left for later (not in this
     item): fetching from a remote registry over the network, key rotation, and dev-dependencies/features.
   - *Fix (2026-11-23, inv227): registry key change needs a relock — status: done.* `build`, `stage` and `vendor`
     compare cuditor.lock's `registry_key` with cuditor.toml's `[registry] key` before reading any index and
     refuse a mismatch with a message naming both keys. A mismatch was already refused, but only indirectly (the
     whole-lock comparison at the end of the check, "cuditor.lock was edited or is stale", after every index had
     been read), which the inv226 trust note wrongly described as unchecked. tests/pkg/run.sh 52 to 57 checks
     (a registry re-signed with a second generated test key: build, stage and vendor refused with nothing staged
     or vendored, a relock records the new key and builds the same hash; a lock whose registry_key was edited
     refused); the four refusal checks fail without the fix.
7. **Sustained adversarial testing**: multi-hour soak runs, syscall and capability fuzzing, and fault injection,
   with the results recorded.
   - *Batch 1 done (2026-11-23, inv225):* `examples/user/sysfuzz.cud`, a ring-3 syscall and capability fuzzer
     (`sysfuzz [SEED [N]]`, xorshift64*). It first calls every syscall gated by a capability it does not
     declare (it has `fs` and `ipc`: 29 numbers for spawn, drv, ktest, kexec, probe, grant and gfx), each of
     which must return `EACCES`, and 20 numbers outside the native table, which must return `ENOSYS`; then N
     calls among read, write, open, close, stat, mmap, munmap, brk, yield, getdents, getargs, dup, openat,
     rights, restrict, chan/send/recv, getpid/getppid, ticks/cpu, kexec generation and unknown numbers, with
     arguments drawn from small and huge integers, kernel, non-canonical, straddling and scratch pointers and
     random path bytes. Calls that could only end or wedge the fuzzer itself are shaped away (no exit, exec or
     fork; fds 0-3 untouched; send and recv only on a channel it tracks; mmap and brk small). It passes if a
     canary nobody was given is intact, the pid is unchanged and the console still writes. The OS suite runs
     `sysfuzz 7 3000` on every boot path (`sysfuzz: PASS`).
   - *Batch 2 done (2026-11-24, inv238):* a soak harness that runs `sysfuzz` across many seeds and
     records the results. `examples/user/syssoak.cud` (`syssoak [START [NSEEDS [N]]]`, defaults
     1, 16, 100) fork+execs `sysfuzz` per seed, prints a stable `syssoak: seed S n N result PASS|FAIL`
     line and a summary, and exits 0 only when every seed passed. `tools/syssoak.cud` is the host
     recorder (`--record IN.log OUT.txt`, `--check OUT.txt [MIN]`, `--self-test`): it writes
     `syssoak-results v1` (one line per seed: seed, n, calls, errors, distinct numbers, capability
     and ENOSYS sweeps, canary, pid, result) and refuses an old-tree log with no soak lines or a
     seed that failed. `tests/os/syssoak.sh` boots once with `incudela.syssoak` on the kernel
     command line (the kernel skips the long shell and kexec sessions, launches `syssoak 1 16 100`,
     and writes `build/os/syssoak-results.txt`); that test fails on the tree before the harness.
     Not a multi-hour soak, and no fault injection (later batches). The kernel unsafe cap stays 709.
   - *Batch 3 done (2026-11-24, inv239):* fault injection in front of sysfuzz. Syscall 408 (still
     capability `ktest` and `ktest_hooks` gated; 409 unchanged) grows three subcommands: `b=2` arms
     the next `a` `kmalloc()` calls to return 0, `b=3` returns the remaining count, `b=4` does one
     probe allocation. The fail counter is checked in the safe `kmalloc` wrapper, so the kernel
     unsafe cap stays 709 (and the count is not raised). `examples/user/sysfault.cud` (`sysfault
     [SEED [N]]`, defaults 1, 50) probes 1+3 forced failures then a live allocation, records a short
     user-space error-path battery (EMFILE, huge mmap denied), and fork+execs `sysfuzz SEED N`.
     `tools/sysfault.cud` records `sysfault-results v1`. `tests/os/sysfault.sh` boots once with
     `incudela.sysfault` (the kernel arms `ktest_hooks` only for that session) and fails on the tree
     before the harness. Alloc-fail is not armed during the default boot or during `file_new` (a
     later batch can harden NULL checks and inject inside ordinary syscalls). Next: multi-hour runs.
   - *Batch 4 done (2026-11-24, inv240):* multi-hour soak support. `syssoak` takes an optional
     fourth argument, a wall-clock budget in `sys_ticks()` units (the 100 Hz LAPIC tick, 10 ms;
     0 means run every requested seed; 360000 ticks is one hour). When the budget expires after
     a completed seed, the program prints `syssoak: checkpoint next S done P fail F budget B
     elapsed E` and exits 0 if no seed failed, so a later session can resume at `S`.
     `tools/syssoak.cud` records a `# checkpoint` line in the existing `syssoak-results v1`
     file (`--check-checkpoint`, `--resume`). `tests/os/syssoak-long.sh` boots once with
     `incudela.syssoaklong` (`syssoak 1 16 100 1`), requires a clean checkpoint after the first
     seed, and fails on the tree before this harness. The existing `os/syssoak` path is
     unchanged (no budget). This is not itself a multi-hour run; a long session is
     `syssoak START NSEEDS N BUDGET` from the shell and is not part of the gate. The kernel
     unsafe cap stays 709.
8. **Real-hardware boot**: a USB image plus a test checklist for Kyle's PC (needs Kyle's hardware).
9. **Linux compatibility measured by real applications**: a list of real apps, each recorded as pass or fail.
10. **Diverse double-compilation check of the bootstrap seed.**

The v1 reservations below still mix in at about one commit in five, and **the other Phase 8 leftovers come
last** (the parked virtio-net interrupt-driven RX with a timed wait, xHCI mass storage and the other open Phase 8
items). Items 2-10 and the never-reboot tiers in Phase 2 follow an outside review (ChatGPT, 2026-11-12), approved
by Kyle on 2026-11-12.

**v1 reservations**, cheap items that keep 1.0 formats and syntax open for Version 2. They are mixed in at about
one commit in five, in this order, each its own commit with a visual and docs:
1. AI-provenance commit trailers: a convention plus a check in tools, applied from then on.
   - *Status: done (2026-11-12).* docs/PROVENANCE.md: the last paragraph of every commit message carries
     `Provenance: human | ai-assisted | ai-generated`, plus `AI-Tool: NAME` for the two AI kinds. `cuditor provenance
     [RANGE]` (tools/provenance.cud) checks every commit from the one that added the tool to HEAD;
     tests/provenance/run.sh (in run_tests) checks 10 fixed messages, a mixed log dump, bad usage and the
     repository's own history.
2. `noalloc`, `noio` and `noreclaim` reserved in the effect grammar (syntax only, no enforcement).
   - *Status: done (2026-11-12).* Grammar v1.3 (docs/GRAMMAR.md, "Allocation effects"): the three names join
     the Phase 6 capability names in EFFECT, so `def f(...) uses noalloc, noreclaim:` parses into the existing
     `Effects` node, round-trips through `--emit=pretty`, and is rejected by the checker with E0106 like any
     effect; outside a `uses` clause they stay ordinary names. Tests: tests/grammar/valid/effects_alloc.cud,
     tests/grammar/invalid/effect_alloc_typo.cud, tests/diag/effects_reserved_alloc.cud.
3. An address-space-ID field in the device-grant ABI, defaulting to 0.
   - *Status: done (2026-11-13).* The device grant (drv 402, `dma_alloc(npages, asid)`) takes an address-space ID as
     its second argument. Only ID 0 exists (the device's one IOMMU domain), so any other ID gets EINVAL before the
     DMA policy check or any allocation; drv 407 with a = 6 reports the number of IDs (`DRV_ASIDS` = 1). blkd checks
     both at start-up and passes 0, so every boot that uses the user-mode driver exercises the refusal; with the
     kernel mutated to accept ID 1 the boot fails at blkd ("blkd: address-space ID 1 not refused"). Per-process or
     per-device-group IOMMU domains can be added later without an ABI change. No new unsafe code.
4. A checksum and version in the handoff/process-state record format.
   - *Status: done (2026-11-13).* The record already had a version (header word +512, `PS_MAGIC << 32 |
     PS_VERSION`, adopted range `PS_MIN_VERSION..PS_VERSION`) and the handoff container its own version (v5) and
     region hashes. Process-state v2 adds a per-record checksum at +520: the FNV-1a word hash of the 64 words at
     +0..+504 with the header word folded in last, so a record verifies on its own (checkpoint, migration and
     record/replay can reuse it outside the kexec container). kexec writes header and checksum last and refuses a
     v2 record that fails it; v1 records (no checksum) are still adopted. `ps_selftest` checks an intact record,
     64 single-bit flips (one per word) and a header flip (all caught) and v1 acceptance. Boot marker:
     `process-state: format v2 (adopts v1..v2), header and checksum checks OK (64 of 64 flipped bits caught)`.
     No new unsafe code (the header store and load became one 16-byte copy each; kernel 170 / 708).
5. CPython bindings on the stable ABI (abi3).
   - *Status: binding layer done (2026-11-24, inv232); the abi3 extension module waits.* Every libpython function
     `tools/cpython/embed.cudi` declares is now in CPython's stable ABI (the pinned 3.13.5 `Misc/stable_abi.toml`,
     none `abi_only`; abi3 floor 3.10, from `PyObject_CallNoArgs`) except the embedding host's four PyConfig init
     functions, which only `forge_py_init` calls: `forge_py_run` and `forge_py_eval` compile with
     `Py_CompileString` and run with `PyEval_EvalCode` in `__main__` instead of `PyRun_SimpleString` /
     `PyRun_String`, and a one-argument call is `PyObject_Call` on a 1-tuple instead of `PyObject_CallOneArg`.
     tests/cpython-embed adds `stable-abi` (each declared function against the pinned list, the four host
     functions really outside it and used only in `forge_py_init`; adding `PyObject_CallOneArg` back, or calling
     `PyConfig_Clear` elsewhere, FAILs it) and error-path checks for run/eval (a raising script, `1 // 0`, and
     `6 *` all fail with the Python error on stderr). Why the rest waits: (1) an abi3 extension module is a shared
     object (`forge.abi3.so`) that a stock CPython loads with dlopen, and Cuditor cannot produce one yet: fas emits
     non-PIC code and fld writes no shared objects (the embed is a `gcc -no-pie` static link); PIC code generation
     and shared-object output come first. (2) The embedding init stays version-pinned on purpose: PyConfig is not in
     the limited API, and the stable `Py_Initialize` would read the environment (no isolated init, no `home`), so
     the 3.13.5 pin, the generated layouts and the libpython guard stay for the host side.
6. The build.sh/run_tests.sh port to Forge, whenever it fits.

---

## Dated schedule (2026-11-15 assessment)

Estimates, not commitments. Pace basis: build/quota-log.txt shows 11 passing batches (39 items) between
2026-11-13 02:01 and 15:49 CST, about 1.25 h per batch of 3-4 items with a 61-minute full gate. The schedule
assumes 8 passing batches (about 24 items) per day the bots run, and that a failed gate costs half a day. Days
without bot usage (as on 2026-11-13 16:30 to 2026-11-15 18:21) move every later date by the same amount. Items
marked *Kyle* need him (hardware, licence, accounts). The core order above is unchanged; the extra items from
the 2026-11-15 assessment (ours and ChatGPT's review, verified against the code) are slotted in where they cost
least.

| Dates (CST) | Item | Size | Notes |
|---|---|---|---|
| Nov 15 | 2: `nown` globals and arrays | 1 batch | done: 7632ffe (inv160; inv159 was cut by a box restart at 20:40) |
| Nov 15 | 2 / 3e: run-queue conversion (`rq_head`, `current`, `idle_thr` to `nown` owners) | 1 batch | done: 5d743d2 (inv161), kernel unsafe 708 -> 701 |
| Nov 15-16 | 2 / 3f: handoff-record conversion (typed `PsRecord`, `KxdRecord`) | 1 batch | done: 0bf232a (inv162), kernel unsafe 701 -> 659; item 2 finished |
| Nov 16 | assessment fixes (README unsafe ceiling, unsafe result names, run_tests OS fail-closed, kernel-core Appendix A count, this schedule) | 1 batch | done: 630410a, bd07324, 94824c4, 0cd8e2c (inv163) |
| Nov 16 | rename and licences: the OS becomes Incudela (Apache-2.0), the language becomes Cuditor (MIT); repo (`kylecurtis477-lab/incudela`), binaries, file extensions, docs; the ESP folder moves from `\EFI\Forge\` to `\EFI\Incudela\` with a one-time migration that keeps the old folder until the new one boots (tools/espmigrate.cud; the loader and kernel read an unmigrated `\EFI\Forge\` meanwhile) | 3 commits + the ESP migration commit (inv165) | *Kyle* approved 2026-11-15; names screened on the web, GitHub, package registries and domains, not a legal clearance |
| Nov 16 | kexec from an older kernel build to the new one (the gate only swaps same-source kernels) | 1 item | tests/os/kexec-compat.sh, results `os/kexec-compat-build`, `os/kexec-old-to-new` (inv164) |
| Nov 16 | SSA step 4d: `--fs-ssa` (opt-in), fsfuzz conditions with `not`/`and`/`or`, CHANGELOG for 0.20.1-0.21.1 | 1 batch | first optimizer pass under the item 3 landing rule (inv175) |
| Nov 16 | SSA: the kernel built with `--fs-ssa` (step 4d kernel switch), dead register writes (step 4e), CHANGELOG 0.22.0 (open) | 1 batch | QEMU boot suite at O2 and O0 (inv176) |
| Nov 16 | SSA step 4f: copy propagation under `--fs-ssa`; step 4g: loader, modules and user programs built with `--fs-ssa`; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv177) |
| Nov 16 | SSA step 4h: the callee-saved registers tracked under `--fs-ssa`; step 4i: single-use moves write their copy's register; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv178) |
| Nov 16 | `--fs-ssa` compile time back down (live phis on a worklist); SSA step 4j: temporaries over straight-line ranges; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv179) |
| Nov 16 | SSA step 4k: phi-crossing temporaries measured (none occur), ranges starting at `xor %eA,%eA` instead; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv180) |
| Nov 17 | SSA step 4l: `push`/`pop` round-trips kept in registers; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv181) |
| Nov 17 | `--fs-ssa` rounds cheaper (identical output), eight rounds instead of four; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv182) |
| Nov 17 | SSA steps 4m (call arguments straight in their registers) and 4n (copies into memory operands); CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv183) |
| Nov 17 | SSA: no phi at a single-predecessor position (fix); step 4o: push/pop round-trips across failure paths; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv184) |
| Nov 17 | `--fs-ssa` rounds cheaper again (identical output); SSA step 4p: copies into %rax; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv185) |
| Nov 17 | SSA: mul does not read %rdx (fix); step 4q: push/pop across calls and mul by a constant; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv187) |
| Nov 17 | SSA step 4r: shift by an immediate; step 4s: drop redundant test after and/or/xor; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv188) |
| Nov 17 | SSA step 4t: sar imm via rcx_lo and sub→lea; step 4u: alu imm via rcx_lo; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv190) |
| Nov 18 | SSA step 4v: mul already in %rax; step 4w: and→test before setcc; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv191) |
| Nov 18 | SSA step 4x: setCC/test/je→jCC when L is flag-safe; jcc-shape; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv194) |
| Nov 18 | SSA step 4y: drop store-reload; step 4z: drop add $0,%rsp; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv195) |
| Nov 18 | SSA step 4aa: imm/zero through %rax into MEM/rD; step 4ab: lea/load into rD; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv197) |
| Nov 18 | SSA step 4ac: imul/reg-store through %rax; step 4ad: add/sub→lea into rD; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv200) |
| Nov 18 | SSA step 4ae: setCC through-merge stop; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 |
| Nov 19 | stop-machine park race fix, irq-off watch split; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv206) |
| Nov 19 | SSA step 4af: unreachable lines after `jmp`; step 4ag: `jmp` to the next label; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv207) |
| Nov 19 | SSA step 4ah: scale into the address; step 4ai: lea folded into the mov; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv209) |
| Nov 19 | SSA step 4aj: `ud2` ends a path; step 4ak: constant index into the displacement; CHANGELOG | 1 batch | QEMU boot suite at O2 and O0 (inv210) |
| Nov 19 | cut 0.22.0: old-name aliases removed, reseed, CHANGELOG 0.22.0 closed | 1 batch | QEMU boot suite at O2 and O0 (inv211) |
| Nov 17 | ownership model write-up: the place/state rules for own, nown, ref, mut, take, replace, swap, including why the syntactic prefix check in `fs_plpre` is sound for differently rooted places | 1 item | ChatGPT shortcoming 1 |
| Nov 17 | gate speed: run the non-QEMU groups of run_tests.sh in parallel, QEMU group alone | 1 batch | done (0.23.0, inv214): 62 items in lanes, lane S (OS artifacts) serial, bounds alone after the lanes, tests/os alone last; `RUN_TESTS_SERIAL=1` keeps the serial run |
| Nov 17 | public CI: .github/workflows that builds, runs run_tests.sh with the OS tests on ubuntu-latest (x86 runners expose /dev/kvm after a udev rule; QEMU from apt) and publishes logs | 1 batch | done (0.23.0, inv215): .github/workflows/ci.yml, jobs build.sh, `SKIP_OS=1 run_tests.sh` O2 and the O0 kernel boot to KERNEL OK (tests/os/ci-boot.sh, TCG); the full OS suite stays the dev-box gate; docs/ci.md |
| Nov 17 | kernel O0 variant: one boot test of a kernel built without the `--fs-*` passes | 1 item | today -O0 still names `--fs-ssa` for the kernel (documented) |
| Nov 18 | data-at-rest keys: RDRAND/RDSEED mixed into the data key, a salted iterated KDF for the passphrase key, key rotation | 3 batches | objd.cudi; batch 1 (fix, RDSEED/RDRAND, PBKDF2 slot v2) done in inv228; batch 2 (two-copy key file, passphrase change, v1-to-v2 upgrade) done in inv229; batch 3 (crash-safe data-key rotation) done in inv231; TPM sealing stays open (no TPM in QEMU tests) |
| Nov 18 | per-CPU run-queue locks plus an SMP scaling benchmark (1/2/4 CPUs) | 1 batch | done (0.23.0, inv216): `rql[q]` per run queue, no lock across `ctx_switch` (`Thread.on_cpu` handshake); `incudela.schedbench` and tests/os/schedbench.sh; yields/s on 1/2/4 CPUs (TCG) about 280k/140k/53k before, 270k/395k/205k after |
| Nov 18 | early USB smoke image and checklist | 1 item | done (0.23.0, inv217): `tools/usb-image.sh` makes build/usb/incudela-usb.img, a reproducible BIOS+UEFI hybrid image with `incudela.smoke` (device-free self-tests only); tests/os/usb.sh boots it as USB mass storage under OVMF and SeaBIOS; docs/usb.md has the write steps and the checklist. *Kyle* boots it once |
| Nov 19-21 | 4: SSA backend for fs/kernel mode, gated by optcov and fsfuzz --combos | 8-10 batches | also a `sqrt` intrinsic (benchmarks need asm today): done (inv233), `sqrt(x)` on f64/f32 compiles to one `sqrtsd`/`sqrtss` in freestanding code (docs/SYSTEMS.md intrinsics; tests/fs/fsqrt) |
| Nov 22 | 5: language server: incremental checks, diagnostics, definition | 3 batches | done (0.23.0, inv218-inv220): include files and `.cudi` diagnostics; comment-only edits not recompiled; references, rename, completion and struct fields through includes; 88 checks |
| Nov 23-24 | 6: package manager: resolution, signed index with publish time and yank flag, reproducible builds | 4 batches | done: 4 batches (signed index, publish, yank; cooldowns; rollback protection; vendor; 52 checks) |
| Nov 25-26 | 7: sustained adversarial testing: a soak harness, a syscall and capability fuzzer, fault injection, multi-hour runs | 4 batches + runs | batch 1 (inv225): `sysfuzz`; batch 2 (inv238): soak harness, short `os/syssoak`; batch 3 (inv239): fault injection (`os/sysfault`); batch 4 (inv240): tick-budget checkpoints and resume, short `os/syssoak-long` (a live multi-hour run is from the shell, not the gate) |
| Nov 27- | 8: real-hardware boot | open | *Kyle*: needs his PC |
| Nov 28-Dec 1 | 9: Linux compatibility by real apps (fork, pipe, file-backed mmap first; app list with pass/fail) | 6+ batches | 39 Linux syscalls today |
| Dec 2-3 | 10: diverse double-compilation of the seed | 2-3 batches | needs an independent compiler path |
| Dec 4- | Phase 8 leftovers; desktop limits (WM_N = 6 windows, one 320x160 app canvas) | open | |

Decided by Kyle 2026-11-15: Incudela (OS, Apache-2.0) and Cuditor (language, MIT); both stay fully open source,
with funding from a separate project. Still open for Kyle: versioned releases on GitHub (none today), turning on the
public CI workflow, and a strict IOMMU default.

## Phase 1 — Interactive multi-process kernel (done)
*Pillars: C, D, F. Closes SYSTEMS.md items 3–5.*

*Fix (2026-11-12, after inv142 O0):* AP start-up waited only 100 ms. A kexec'd kernel's AP missed it ("did not
start"), the BSP unmapped the trampoline, and the AP then enabled paging on a missing page and reset the machine
(os/kernel-bios, rc 0). Now: up to 1 s per AP, a claim word decided by `atomic_swap`, and INIT for an AP that never
claimed, before the trampoline goes away. Reproduced with a delay inside the trampoline's 32-bit stage: the old code
reset exactly as in inv142; the fix brings a 300 ms AP up late and parks a 1500 ms AP (3/3 CPUs used, the next
kexec'd kernel starts all 4). The committed knob `forge.ap_delay=MS` delays the last AP at the top of `ap_main`.

| Deliverable | Test that proves it |
|---|---|
| FPU/SSE/AVX state saved with xsave/fxsave on every context switch **(done, b14b23e)** | User programs fill xmm0–15, yield 20 times across 4 CPUs, and verify every register |
| SMEP + SMAP, with copy_user/copy_str_user and #PF fixups **(done)** | Probe syscall: a kernel read without `stac` is blocked and a kernel call into user code is blocked; bad pointers return EFAULT |
| TLB shootdown IPIs; frames reused only after the shootdown **(done)** | Pinned readers on all CPUs see the new frame after a global page is remapped |
| Wait queues, sleeping mutexes, condvars, `sleep_ticks` **(done, 2ba9709)** | Mutex-protected counter that yields inside the critical section; a producer/consumer ring; no lost wakeups over 10k iterations |
| Proc objects: fork (eager copy), exec, wait, exit, brk, anonymous mmap/munmap, getargs **(done, f1d151f)** | `forktest`: parent and child diverge memory, the child execs `hello`, and the parent's wait returns its code. A brk/mmap stress test frees every frame (leak = 0) |
| VFS with fd table: open/read/close/stat/getdents; FAT32 long names (LFN) **(done, f1d151f)** | `cat` reads `\EFI\Incudela\docs\Long File Name Notes.txt` (path with spaces); the read byte count matches `stat`; `ls /EFI/Incudela` shows case-preserved names |
| virtio-blk with MSI-X interrupts; requests sleep instead of polling **(done)** | Boot test: every request after MSI-X setup completes by interrupt (211 requests = 211 completions = 211 sleeps, 0 polled) |
| PS/2 keyboard (IRQ1) and COM1 RX (IRQ4) feeding one tty input queue **(done, f1d151f)** | The harness types `ls`, `forktest`, `nosuch` and `ls /EFI/Incudela` (shifted keys) through QEMU `sendkey`, and `cat …`, `hello a b` and `exit` over COM1 |
| User-mode Forge shell `sh` loaded from disk: `ls`, run a program (fork+exec+wait), `exit` **(done, f1d151f)** | Boot test reaches `sh$`, lists the programs, runs `hello`, gets its exit code, and then reaches KERNEL OK |

## Phase 2 — Never reboot: self-healing, live-updatable system (signature feature 1)
*This phase needs Phase 1's processes, services, and wait queues. Each sub-step is finished and tested before the next one starts.*

**The never-reboot promise has three tiers** (outside review, ChatGPT, 2026-11-12), each claimed only as far as
its tests go:
- *Tier 1, service restart*: a crashed or updated user-mode service (driver, input, storage) restarts without a
  reboot, and its clients keep their state (done for blkd, kbdd, the NVMe service).
- *Tier 2, live driver update*: a running driver is replaced by a new version in place, with its state handed
  over (the kbdd v1/v2 swap, kernel modules with save_state/restore_state).
- *Tier 3, live kernel replacement*: kexec handoff to a new kernel with the processes kept. It needs a written
  state-transfer contract (the process-state record format), rollback to the old kernel when the new one fails
  its checks, and tests with I/O in flight across the switch. Until those exist it is not claimed as finished.
1. **Kernel module ABI.** Relocatable Forge modules (ELF ET_REL) are loaded and unloaded at runtime. They get a versioned symbol table and an explicit `init/exit/save_state/restore_state` contract. Test: load, call, and unload a module 1000 times with no leaks.
   - **Status: done.** `examples/kernel/module.cudi`; test modules in `examples/modules/` (cudc + `as` → `.ko`, shipped in `\EFI\Incudela\mod\`). KABI 1.0: exports carry a since-minor; wrong major, newer minor, imports newer than the module's ABI, unresolved symbols and truncated images are rejected. Relocations R_X86_64_64/PC32/PLT32/32S with range checks; sections mapped W^X in 1 MiB slots at `0xFFFFFFFFD0000000`. Boot test: 1000 load/call/unload cycles, 0 frames and 0 heap bytes leaked, save/restore state across reload, 4 bad modules rejected.
2. **Drivers as isolated services.** Each driver (virtio-blk, tty/keyboard, later the network) runs as a user-mode or isolated service process. It reaches its device only through granted MMIO/IRQ/DMA capabilities and talks to clients over IPC. Test: injecting a crash into the driver service leaves clients alive.
   - **Status: done (virtio-blk).** `examples/kernel/drv.cudi` + `examples/user/blkd.cud`. The ring-3 `blkd` gets capability syscalls 400–407: port I/O checked against the device's 64-byte I/O window, MSI-X interrupt wait, one contiguous DMA region mapped into it, recv/reply IPC. `vb_read` (so FAT and all file I/O) is routed to it after a handover under `vb_m`. On driver death the kernel resets the device before the DMA frames are freed and fails the in-flight request with EIO. Boot test: init.elf read through blkd is byte-identical; a non-driver caller gets EPERM; an injected NULL write with a request in flight on the device kills blkd (#PF, exit 0x10e), the client gets EIO and continues, the kernel driver takes the device back, 0 frames / 0 heap bytes leaked. Gaps: one request in flight, tty/keyboard still in-kernel; broader device grants stay gated. VT-d DMA confinement (done): `iommu.cudi` walks the ACPI DMAR table after `acpi_init` and before `pmm_reclaim` (width-1 mmio_rd of a temporary window, no new unsafe functions or blocks). After `pci_scan`, `iommu_enable()` programs every remapping unit and turns translation on with default deny (see IOMMU hardening below); a blkd DMA grant is mapped at a non-identity IOVA in a second-level page table that contains only those pages, and drv 403 returns that IOVA (without a remapping unit, 403 still returns the host PA). On driver death the grant is unmapped and the device returns to its kernel pass-through context before its frames are freed, so `vb_reinit` can program host PAs again. Test: tests/os/run.sh `os/kernel-iommu` boots the ISO on q35 with `-device intel-iommu` (now `intremap=on`, see gap 2 below) and a modern virtio-blk (`disable-legacy=on,iommu_platform=on`, so QEMU offers ACCESS_PLATFORM and translates DMA; transitional virtio bypasses the IOMMU) and checks the remapping-unit line, `translation on`, `drv 403 returns IOVA`, `slpt maps only the grant`, and KERNEL OK (blkd still serves the disk). The seven DMA/IOMMU gaps first listed here (pass-through default, interrupt remapping, first DRHD only, fault logging, RID aliasing, context-table coverage, policy without an IOMMU) are all closed; docs/kernel-core.md Appendix A.2 records each fix and its remaining limits, and the IOMMU hardening entries below give one line per change.
   - **IOMMU hardening (the seven DMA/IOMMU gaps in docs/kernel-core.md Appendix A.2).** One short entry per change:
     - *Default deny, every remapping unit, context-table audit (gaps 1, 3, 6) — done.* The root table starts empty. A requester ID gets a context entry only when the kernel drives the device itself (`pci_busmaster` calls `iommu_claim` before setting the bus-master bit: pass-through, domain 1) or a DMA grant covers it (translate, domain 2). Every other scanned device, and every requester ID the scan never saw, has no entry, so the IOMMU blocks its DMA. Context tables are allocated per bus on demand (up to 8 buses). All DRHDs the probe found are programmed with the shared root table and invalidated together (second-level width = the widest one all units support). `iommu_audit` walks all 65536 requester IDs: present entries must be exactly the claimed and granted ones with the right type and domain; a self-test plants a stray pass-through entry and requires the audit to catch it. Pins (`os/kernel-iommu`): `translation on, 1 of 1 remapping unit programmed (default deny`, `VT-d: default deny: `, `context audit: 65536 requester IDs, `, `0 stray, 0 missing`, `context audit catches a stray pass-through entry`. Unsafe counts unchanged.
     - *DMA fault recording and requester-ID aliasing (gaps 4, 5) — done.* `iommu_fault_drain` reads FSTS and every fault-recording register (offset and count from CAP), prints `VT-d fault: unit, source BB:DD.F, reason 0xNN (text), read of / write to ADDR`, and clears them (fault interrupts stay masked; faults are polled). `iommu_aliases` computes the requester IDs a device's DMA can carry: behind a PCIe-to-PCI bridge, (secondary bus, devfn 0); behind a conventional PCI bridge, the bridge's own ID; PCIe ports do not alias. Claims and grants install an entry for every alias. Test: the `os/kernel-iommu` boot adds QEMU's `edu` device behind a root port and a `pcie-pci-bridge`. `iommu_dma_selftest` turns on edu's bus mastering without claiming it, then (1) a DMA must fault with the alias as source and reason root/context entry not present, (2) a test domain on the alias maps two pages at IOVA 0x800000 and 64 bytes go into edu and back out to the second page, identical, with no fault, (3) a DMA 16 pages past the mapping must fault at exactly that IOVA. Then bus mastering is turned off, the test domain removed, the audit re-run and the frames freed. Pins: `(alias via PCIe-to-PCI bridge `, `denied edu DMA faulted: source `, `requester-ID context(s): 64 bytes into edu and back`, `identical, 0 faults`, `out-of-grant edu DMA faulted at IOVA 0x0000000000810000: source `.
     - *Policy for a machine with no remapping unit (gap 7) — done.* Written policy, printed at boot by `iommu_policy_report`: with remapping active, `VT-d policy: remapping active (deny by default, grants confined)`. Without a usable unit (no DMAR table, no DRHD, or `iommu_enable` failed), the default is permissive, so existing machines keep their disks: kernel drivers and drv 402 grants use host physical addresses, and the log says `VT-d policy: no remapping unit, DMA unconfined (permissive default: …)`. A strict policy (`iommu_strict`, build-time default `IOMMU_STRICT_DEFAULT` = 0, since the kernel has no command line yet) refuses drv 402 with EPERM through `drv_dma_check`, the same gate `sys_drv` uses (after the driver-capability check, before any allocation). Boot self-test on every no-IOMMU boot: strict mode returns EPERM, permissive returns 0. Pins: the two policy lines in the shared marker set of `os/kernel-bios`, `os/kernel-uefi` and `os/efi-loader-gpt`, and the remapping-active line in `os/kernel-iommu`.
     - *Runtime switch (2026-11-12).* `boot_policy` (examples/kernel/bootpol.cudi) sets `iommu_strict` at boot, after the
       ESP is mounted and before any user-mode driver starts, from three inputs in order: the build default (unchanged,
       permissive); `\EFI\Incudela\boot.cfg` only if it carries a valid kind-2 seal (`cudseal --config`, checked by
       `image_verify` with `SEAL_CONFIG`; `iommu=strict` or `iommu=permissive`; an unsealed, tampered or malformed config
       is refused whole and logged); then the boot command line (`BootInfo.cmdline`, from the multiboot2 tag and copied
       across kexec), where `incudela.iommu=strict` tightens and `incudela.iommu=permissive` is refused, so an unsigned line can
       never loosen the policy. The rule is the pure `pol_resolve`, whose 18-row truth table (including a strict build
       default, where only the sealed config loosens) is checked on every boot. Under strict without remapping the drv
       test checks the refusal end to end: blkd gets EPERM from drv 402, exits 1, the in-kernel driver keeps the disk
       (init.elf read back identical), nothing leaks; the shell and kexec sessions, which need blkd, are skipped and
       logged. Safe code only: unsafe stays 170 functions / 709 ops. Tests (tests/os/bootpol.sh, one boot per mode):
       `os/bootpol-cmdline-strict` (GRUB with `incudela.iommu=strict`, tampered config refused), `os/bootpol-iommu-kexec`
       (intel-iommu, a sealed permissive config overridden by the command line, the same policy in the kexec'd
       generation-1 kernel), `os/bootpol-config-strict` (native loader, sealed strict config); the default is pinned in
       the shared marker set (`boot policy: DMA policy permissive (build default`). os/result-count 35 to 38.
     - *Interrupt remapping (gap 2) — done.* When every unit reports IR and QI, `iommu_ir_enable` turns on queued invalidation (one 256-descriptor queue per unit; context, IOTLB and interrupt-entry-cache invalidations and a wait descriptor with a status write; the legacy invalidation registers are no longer used once it is on), installs one shared 256-entry remapping table (IRTA, SIRTP), allows compatibility-format interrupts (CFI, for the IOAPIC) and sets IRE. `iommu_ir_route` writes a source-validated IRTE (fixed delivery, edge, physical destination; SVT = 1, the device's DMA requester ID) and the caller programs a remappable-format message (handle in the address, data 0); virtio-blk's MSI-X uses IRTE 0, so every blkd request after this is an interrupt that went through remapping. Self-test with edu's MSI: through IRTE 1 (validated for edu's requester ID) the test vector arrives once; through an IRTE validated for another requester ID, and through a not-present IRTE, nothing arrives. The `os/kernel-iommu` command line now uses `intremap=on`. Pins: `VT-d: interrupt remapping on (256-entry table`, `vector 0x50 -> IRTE 0 (source `, `VT-d IR: edu MSI via IRTE 1 (source `, `delivered 1; via an IRTE validated for `, `blocked; via a not-present IRTE blocked`.
   - *No-restart gap 1 closed (tty/keyboard as a supervised, hot-swappable ring-3 service).* `examples/kernel/kbd.cudi` + `examples/user/kbdd.cud` / `kbdd2.cud`. During the shell session the PS/2 and COM1 IRQ handlers only append raw bytes to a 256-entry kernel journal (`kind<<8|byte`); decoding (scan-code set 1, shift, E0, CR→LF) runs in the ring-3 driver `kbdd` (DRV_KBD, caps(drv), no root fd). Syscalls 411 recv (block for a batch of ≤32 entries; 0 = quiesce), 412 commit (end seq, decoded chars, decoder state word, applied to the tty under rq_lock in one step) and 413 get-state are CAPB_DRV and only for the registered pid. Uncommitted entries stay in the journal, so a dead driver's batch is replayed by its successor, which starts from the last committed state. Two different implementations share the state format (v1: one shift bit, shifted table; v2: left/right shift bits 0 and 2, arithmetic upper case); a swapper asks the running one to quiesce every 10 ticks and the supervisor starts the other. A swap request waits until the running driver has entered recv once, so each instance takes at least one batch (2026-11-12 fix: the service was marked up before the spawn, which includes the Ed25519 seal check, so a spawn slower than 10 ticks under host load had every new driver quiesced on its first recv and input never reached the shell, the inv134 kernel-uefi hang); a test hook requests a swap right after each of the first 3 starts and the boot fails if any driver was quiesced before its first recv (`input service: N swap request(s) held until the new driver reached recv, 0 driver(s) quiesced before their first recv`). A crash (exit ≠ 0) is restarted the same way, at most 5 times, after which the kernel decodes again. `crash k N` (syscall 408 b=1, still ktest_hooks-gated) makes the batch holding the N-th next entry carry a fault flag; the driver then dies on a bounds trap (#UD). At session end the service is stopped and the kernel decodes any leftover entries with the same state. Boot test: `crash k 4` then `hello Swap OK` typed over the PS/2 keyboard while swaps run: kbdd v1 dies, "restart 1, replaying from entry …", the line arrives intact (`hello: args = 'Swap OK'`), ~36–60 hot swaps, entries in == committed + kernel-drained, dropped 0, lost 0. Also fixed: driver spawns marked the driver kind in a global, so an ordinary process spawned concurrently on another CPU could come up as a driver without a root fd; the kind is now per spawning thread (`Thread.spawn_drv`), and `proc_reap_orphans` leaves driver processes to their supervisor. Gaps: the echo path and line discipline stay in the kernel (the modules of item 4); the journal holds 256 entries (overflow is counted as dropped and fails the test).
   - *No-restart gap 2 closed (NVMe as a supervised, hot-swappable ring-3 service).* `examples/kernel/nvsvc.cudi` + `examples/user/nvmed.cud` / `nvmed2.cud`. `nvme.cudi` splits commands into `nv_submit`/`nv_reap`; when the service is on, `nvme_read/write/flush` go through `nv_io` → `nvs_call`, which hands the request to the ring-3 driver `nvmed` (DRV_NVME, caps(drv), no root fd). Syscalls 414 recv (0 = quiesce), 415 submit (opcode/LBA/count checked exactly against the pending request, writes only inside the Incudela partition; anything else refused and counted), 416 reap, 417 reply (seq, status, state word with magic in bits 63:32 and served count), 418 get-state; all CAPB_DRV and registered-pid only. A dying driver's in-flight CQE is drained by the kernel and its request is replayed to the successor. A swapper alternates v1/v2 every 7 requests; ffs_test arms a crash on request 30. Boot test (both forgefs boots): restart 1, replayed ≥1, drained ≥1, ≥3 swaps, forged SQEs refused (v2 probes one at start), served count carried == requests. Also: a driver with an all-bss RW segment had p_offset past the file end and was refused by elf_load; the drivers carry one initialized word. Gaps: admin queue, interrupts and the queue memory stay in the kernel.
   - *No-restart gap 3 closed (more than one live-patch site).* `livepatch.cudi` keeps a table of up to 8 registered `@patchable` sites, each with its own text hash and patched flag (`lp_find`, `lp_site_hash`, `lp_npatched`; registering twice is a no-op, a 9th site gets LP_EFULL, applying to an unregistered address is refused). Second site: `sys_getppid` (syscall 110), now `@patchable` over the unpatchable helper `kcur_ppid` (exported to modules). `getpid2.ko` carries replacements for both plus a wrong variant of each; its counters moved to shared helpers, so its unsafe counts went down (3 0 4 0). Boot test: hammers on 3 CPUs call both syscalls; 25 rounds patch both sites, check both are live, then revert them one at a time in alternating order, checking after each revert that the other site is still patched; both wrong replacements are rejected (rejects 2); both hashes restored and neither patch reached after revert; 0 wrong results, 0 leaks. Gaps: the quiescence check is still the hammers' counters rather than a stack walk; multi-site patches are applied one site at a time (no single stop-machine transaction across sites).
   - *No-restart gap 4 closed (driver state carried across the kexec handoff).* The kexec session now runs with the supervised input service (kbdd) on. With every other CPU halted and input interrupts off, `kxd_save` writes a driver-state section into the handoff header page past KXH_BYTES (own magic and hash, so the v3 format and its adoption rules are unchanged): driver kind and version, the decoder state word, the journal entries not yet committed and the service counters. The new kernel's `kxd_adopt` validates it before the region is freed, and `kbd_service_start_from(1)` starts the same driver version on the carried journal and state instead of a fresh service. Boot test (BIOS and both UEFI boots): a shift press + release is queued at handoff time where no driver in the old kernel can take it; the generation-1 driver replays the 2 carried entries (entries committed ≥ carried + 2), commits keep counting from the carried total, restart/swap counters carry over, dropped 0, then the shell types `hello after kexec` through it. Gaps: only the input service has a record (the NVMe and block services are not running across the test's handoff and still start fresh); driver processes themselves are restarted, not carried.
   - *True self-hosting, step 1 (seed replaces the Rust bootstrap).* `seed/cudc-seed` is a checked-in cudc binary (the fixpoint compiler, built by fas/fld), pinned by `seed/cudc-seed.sha256`, which build.sh checks before using it. build.sh no longer runs `cargo`: the seed compiles tools/embed.cud and selfhost/cudc.cud (stage2); stage2 → stage3 → stage4 must still be byte-identical, and build.sh reports `SEED OK` when the rebuilt compiler is byte-identical to the seed (`SEED NOTE` after a compiler change, until `tools/reseed.sh` refreshes it). The Rust bootstrap is an optional cross-check: `FORGE_RUST_CHECK=1 ./build.sh` builds src/main.rs and checks that its stage1 emits the same stage2.s. Verified with `target/` removed. Step 2 done (below).
   - *True self-hosting, step 2 (no binutils in the build).* `seed/fas-seed` and `seed/fld-seed` (pinned with cudc-seed in `seed/seed.sha256`) assemble and link embed, stage2 and the stage2-built fas/fld; every later stage uses the freshly built fas/fld. build.sh reports `SEED TOOLS OK` when the rebuilt fas/fld are byte-identical to the seeds. Verified with `as`, `ld`, `cargo` and `rustc` blocked on PATH: FIXPOINT OK from the seed. GNU as/ld remain only as reference oracles in tests/fas and tests/fld.
3. **Supervisor with automatic restart.** Death is detected, the service restarts with its saved state, and in-flight requests are replayed idempotently. Test: the boot test kills the block driver in the middle of `cat`, and the output is still byte-identical; the restart count is reported.
   - *Status: done.* For the whole shell session `blkd` runs under a supervisor kernel thread (`drv.cudi`). The boot script runs `crash 40` (syscall 408, a fault-injection hook) and then `sum` on the 96 KiB `\EFI\Incudela\docs\big.bin`. blkd dies with a request in flight. The supervisor reaps it, respawns it from the cached image with its restart generation as an argument, and the kernel-held request journal replays the read. Replies are matched by sequence number, so a stale reply cannot complete a newer request. The FNV-1a hash of the file matches the one computed on the host, and the test reports "blkd restarts 1 … replayed 1". After 5 restarts the supervisor gives up and fails requests with EIO. The session leaks 0 frames and 0 heap. Gaps: the test file is read with `sum` (which hashes it) rather than `cat`, so the comparison is by hash; the device is the only driver state, and it is rebuilt on restart (there is no state blob to save); there is one request slot; writes are not replayed, since only reads exist.
4. **Hot-swap with state transfer.** Replace a running driver or module with v2. The old version quiesces, serialises its typed state, the new version restores it, and clients see only latency. Test: swap the tty driver while the shell is reading, and no keystroke is lost.
   - *Status: done.* The tty line discipline goes through three function pointers: push, lines and pop. v0 is built into the kernel, and `tty1.ko` (a 512-byte head+count ring) and `tty2.ko` (a 1 KiB ring with free-running indices, which recounts lines on restore) are interchangeable modules that share one state format. During the shell session a swapper thread cycles v1↔v2 every 2 ticks, and at the end it swaps back to v0. Each swap loads the new module, then, under rq_lock, saves the old state, restores it into the new module and switches the pointers. All tty calls run under rq_lock, so no CPU can still be in the old code when it is unloaded. If a restore fails, the swap is aborted. Boot test: about 120 swaps, about 40 of them with a partial line queued; pushed == consumed + erased, lost 0, dropped 0; no leaks. Gaps: the swap is triggered by a timer rather than by an operator command; the echo path is not part of the module. The fault-injection syscall 408 now returns EPERM unless the kernel's boot self-test has armed it for its shell session, and drv_test checks this.
5. **Live kernel patching.** Function-level patches are applied with stop-machine via IPIs. Each patched function gets a jump at its entry, verified by its hash. Rollback is supported. Test: patch `sys_getpid` while 4 CPUs hammer it; results switch atomically and rollback restores them.
   - *Status: done.* cudc (both `selfhost/cudc.cud` and the embedded `compiler.cud`) has a new `@patchable` decorator that emits a 5-byte nop (`0f 1f 44 00 00`) at the 16-byte-aligned function entry. `sys_getpid` is `@patchable`. `livepatch.cudi` registers the target, recording an FNV hash of its first 32 bytes. To apply a patch it checks the nop and the hash, then writes `jmp rel32` to the replacement in `getpid2.ko`. The write is a single aligned 8-byte store through the HHDM alias, so kernel text stays read-only. It happens under stop-machine: the other 3 CPUs are parked with interrupts off in the shootdown IPI and serialise with cpuid before continuing. Revert writes the nop back and re-checks the hash. `lp_apply_checked` tests the replacement before installing it (the wrong `lp_getpid_bad` is rejected and never becomes reachable), then tests the live entry point and rolls back if that fails. Boot test: 3 hammer threads on 4 CPUs make about 2.5 M calls while the patch is applied and reverted 25 times (about 1.5–1.9 M of the calls go through the patch); 0 wrong results; 1 rejection and 1 rollback; hash restored; patched code is not reached after rollback; 0 leaks; 6 back-to-back OS test runs passed after a stop-machine round-generation fix (a CPU that missed the release could get stuck into the next round). Gaps: only one patch site is tracked (closed by no-restart gap 3); the module is unloaded after a quiescence check based on the known callers (the hammers' loop counters plus an in-patch active counter), not a general stack walk; user processes call getpid through the same entry, but the test does not run them concurrently with the patching.
6. **kexec-style handoff (fallback).** Boot a new kernel image while keeping user state: process memory, fds, and the console are serialised into a handoff region the new kernel adopts. Dual-boot rules still apply, and nothing is written to disk. Test: the shell survives a full kernel replacement and the next command works.
   - *Status: done.* Syscall 409 (`kexec`, only when `ktest_hooks` is set, like 408) is in `kernel/kexec.cudi`. It pins the caller to the BSP (CPU 0) and sleeps until it runs there, so the successor's INIT-SIPI never hits a parked old BSP. It reads `\EFI\Incudela\kernel.elf` from the read-only ESP, verifies it, and copies its PT_LOADs to a 2 MiB-aligned free physical range. It then builds a handoff region in free frames. The region holds: a header (magic, generation, brk, pid, FNV hash), a fresh BootInfo (`BOOT_KEXEC`, memory map with the region marked `MEM_HANDOFF`, saved RSDP copy), loader-style page tables, an identity-mapped jump stub, the FPU state, the syscall frame, args, and an index of every present 4K user page plus its data. To quiesce, it switches off input, resets virtio, masks the IOAPIC and LAPIC timer, and parks APs under stop-machine with `tlb_halt`, then jumps. The new kernel boots normally (its own ACPI/SMP/drivers), sees `bi.handoff`, checks the hash, rebuilds the process (pages, brk, args, console fds 0–2, FPU), and resumes it in a fork-style thread that returns 1 from the syscall. It then frees the region. Boot test (`boot.py`: `hello x`, `kexec`, `hello after kexec`, `exit`): the shell keeps its command counter across the swap (pid 52 → 34, 21 pages, 140 KiB region), runs the next command, and exits 0. `os/kexec-no-disk-write` checks the sha256 of the GPT disk image is unchanged after the efi-loader-gpt boot. All three boot paths pass, 3 back-to-back runs. Gaps: only the calling process survives (others, kernel threads, modules, and driver state are not carried over; drivers re-probe); only console fds survive; ACPI reclaim memory is no longer reclaimed so the successor can reparse tables; same kernel image (no version negotiation of the handoff format beyond the magic).
   - *Hardening (format v2):* `kexec next` (409 with arg 1) loads `\EFI\Incudela\kernel-next.elf`, a genuinely different build (kernel/build.sh rewrites the version string to `incudela-kernel 0.2.6-next` and fails if the ELFs are identical). The sender freezes every non-driver user process at a syscall boundary (syscall_dispatch entry, or inside the sys_wait / tty_read block loops; per-thread `sc[5]` records nr+args since the 80-byte frame lacks them), waiting up to 300 ticks, else prints "handoff abandoned" and returns EBUSY. Header v2 (448 B): magic, version, min/max accepted, sizes, counts, separate data and metadata FNV hashes, section page offsets, sender version string, RSDP copy. Per process: 2 pages (record + FPU); shared File objects are deduped into a 64 B/file table and refcounted on restore. Receiver prints the sender/own version and accepted range, drops processes on an unsupported version, keeps pids (fresh pid + ppid remap on collision, next_tid bumped), carries zombies, and resumes parked syscalls via `kx_restart_entry` (callers get 1 via `kx_resume_entry`). Syscall 410 returns the generation (ungated). New `user/bg` reads half of a 96 KiB file, waits for generation 1, reads the rest through the carried fd and checks a 16 KiB heap pattern. Boot test: `bg 1 &`, `hello z &`, `kexec next`, `hello after kexec`, `wait`: 3 processes (pids 52/54/55 kept), 2 files, 46 pages, 264 KiB region; bg matches a fresh read; `wait` reaps 54 and 55 exit 0. Gaps: a pure user-mode spinner that never syscalls makes kexec return EBUSY (no IPI-based preemptive parking); drivers are restarted, not carried; only one format version exists and there is no negative test for an unsupported version.
   - *Format v4 (Phase 11.1a):* the process record carries the 128-byte syscall frame (argument registers saved, as the Linux ABI needs) and the process ABI (word +56, bit 40); a v4 kernel adopts only v4.
   - *Format v5 (v1.3 item 7):* each process record is a process-state v1 record (pstate.cudi) with its own header word; the receiver refuses a record whose header it does not support.

## Phase 3 — Machine-readable compiler and test tooling
*Pillars: B, C.*
1. `cudc --diagnostics=json` emits file/line/col, a code, a message, and fix-it spans for every error. Test: a golden JSON file for each error class in tests/diag.
   - *Status: done.* `cudc in.cud out.s --diagnostics=json` prints one JSON object per error on stderr (schema v1: `version, severity, code, file, line, col, end_line, end_col, message, fixits[]`; 1-based columns, end exclusive; a fix-it replaces `[col,end_col)` on its line with `replace`, plus a `note`). Both the parser/codegen path (`die`) and the type checker (`tc_err`) route through `diag_emit`; lexer errors record the exact offset, name errors locate the quoted identifier on the line, type errors use the token position. Each source carries its file name (imports report their own file). Codes: E0001–E0003 file/include, E0100 other parse/codegen, E0101 bad character, E0102 unterminated string, E0103 indentation, E0104 newline in f-string, E0105 expected (parse), E0106 reserved effect annotation (v1.2), E0201 undefined function, E0202 undefined name, E0203 unknown method, E0300 other type error, E0301 argument type, E0302 assignment, E0303 operand types, E0304 missing argument, E0305 missing return, E0306 return type, E0307 index type, E0308 int literal range, E0309 unknown keyword, E0310 unary operand, E0311/E0312 list/str index, E0313 return value expected, E0314 parameter default, E0315 arity. Fix-its: delete a bad character, close an unterminated string at end of line, re-indent to the enclosing level, and "did you mean" replacements for undefined names/functions/methods (closest user identifier, edit distance ≤2). Text output without the flag is unchanged. Tests: 30 golden files in `tests/diag` (all error classes from tests/errors and tests/typeerrors plus typo, keyword, unary, list-index, EOF-string cases), a schema check of every golden line, and a missing-input check. Gaps: only the first error is reported (the compiler stops at it); type errors other than names have no fix-it yet; columns are byte columns.
2. `cudc --emit=ast-json` produces a stable, versioned AST schema. Test: a round-trip, AST → pretty-printer → AST, is identical for the whole selfhost compiler.
   - *Status: done.* `cudc in.cud out.json --emit=ast-json` writes `{"forge_ast":1,"file":F,"pragmas":[...],"root":NODE}` with `NODE = {"k":KIND,"l":LINE[,"v":VALUE][,"c":[children]]}`; `--emit=pretty` writes canonical source from the same tree. The AST comes from a separate strict recursive-descent parser (`a_*` in compiler.cud) over the raw token stream of one file (no prelude, no include inlining, no std-module renaming); f-strings appear in their desugared `"" + ... + str(x)` form and `# cuditor:` pragma lines are kept because they change code generation. Node kinds are listed in docs/SYSTEMS.md. Tests (tests/ast, run by run_tests.sh): `roundtrip.sh` — for 107 files (compiler, prelude, tools, every test, every example and kernel .cudi) AST(src) == AST(pretty(src)) ignoring line numbers, and pretty is a fixpoint; `semantic.sh` — all 44 pretty-printed tests/*.cud programs compile and print the same .expected output; `selfpp.sh` — the pretty-printed selfhost compiler builds a compiler whose output on cudc.cud is byte-identical; plus a schema check. Gaps: comments other than pragmas are dropped (fmt in item 4 works at token level for that reason); f-strings are not re-sugared; the pretty-printer keeps parentheses on value tuples and value subscripts (`d[(1, 2)]`) because Forge types them differently from bare tuples.
3. Grammar freeze:
   - an EBNF in docs/GRAMMAR.md;
   - a conformance suite that parses every example;
   - a test that fails if the parser accepts anything outside the grammar (fuzzed with a grammar-based generator).
   - *Status: done.* docs/GRAMMAR.md (version 1) is an EBNF of the whole language — lexical classes, statements, the 15 expression precedence levels, comprehensions, params, targets — with each rule tied to the `a_*` parser function that implements it; the strict AST parser is the reference. Conformance (tests/grammar/run.sh, run by run_tests.sh): `valid/all_productions.cud` uses every production and must parse; 30 `invalid/*.cud` programs (missing colon, dangling operator, unbalanced brackets, decorator without def, try without handler, bare yield argument, `0b` literal, …) must be rejected with an E0100–E0105 diagnostic; every example, kernel .cudi, tool, test and the compiler must parse (item 2 round trip). `tools/grammar_fuzz.py` generates random programs from the grammar (deep expressions, all statement forms, nested blocks): valid ones must parse and round-trip through the pretty-printer to the same AST, and one-line mutations that leave the grammar (unbalanced, dangling, `= =`, bare keyword, header without block, header without `:`) must be rejected cleanly. CI runs seed 1 with 160 programs; seeds 1–5 were run by hand and pass. Findings while freezing: `@=` is not an operator, `0b`/`0o`/`r""` literals do not exist, and EOF errors now report the last line instead of line 0. Gaps: the fuzzer's invalid oracle is mutation-based, not a full grammar complement; the code-generating parser still accepts a few legacy forms beyond the grammar (it is not the one fuzzed).
4. `cuditor fmt` is a canonical formatter. Test: it is idempotent on all sources, and the repo is kept formatted in CI.
   - *Status: done.* `cuditor fmt [--check] [files]` (tools/fmt.cud, built to build/fmt on demand; no files = the repo set from `build/fmt --list` (tools/fmt_files.sh is the reference)) is a line/token-level formatter, so comments survive: 4 spaces per block level, continuation lines keep their offset from the opening line, single spaces between tokens, none after openers / before closers, commas and colons, one after a comma, two before an inline comment, no trailing whitespace, at most 2 blank lines, none at file start/end, one final newline; triple-quoted string contents are untouched. The whole repo (110 files, incl. compiler.cud) was formatted; ast-json of every file, line numbers included, was identical before and after, and FIXPOINT holds. tests/fmt/run.sh (in run_tests.sh): golden, idempotence, --check detects, repo is fmt-clean, AST-preserving on a formatted copy. Gaps: no line wrapping or operator-spacing normalisation beyond whitespace collapse; error fixtures (tests/diag, errors, typeerrors, grammar/invalid) are excluded because their goldens are column-sensitive. `fmt --help` (or `-h`) prints usage and exits 0; an unknown option or a missing file is a one-line error with exit 2 (it used to segfault reading the missing file as `None`); tests fmt-help, fmt-bad-option, fmt-missing-file.
5. `cuditor test` runs inline `test "name":` blocks and gives a JSON report. `cuditor verify` runs the Phase 4 checkers as a gate.
   - *Status: done.* `test "name":` blocks (grammar v1.1 soft keyword, AST node Test, pretty-printed), `cudc --test` runner, `cuditor test` (per-test process isolation, 10 s timeout, JSON report) and `cuditor verify` (parse + fmt + build + test gate, JSON report); see SYSTEMS.md. tests/unit/*.cud hold the first 7 unit tests; tests/testblocks/run.sh (8 checks, in run_tests.sh) covers the JSON schema, failure detection, quoted names, normal builds ignoring tests with line numbers intact, AST/pretty, and verify catching fmt and parse failures. Gaps: no fixtures/setup sharing, no per-test filter or parallelism; a file's top-level code runs before its tests; the header rewrite is line-based, so a column-0 `test "x":` line inside a triple-quoted string would be rewritten; verify has no type-only or effect checker yet (typecheck runs as part of build).

## Phase 4 — Memory-safe Cuditor by default
*Pillar: A. Closes SYSTEMS.md item 6.*
1. **Slices** `[]T` carry (ptr, len), with bounds checks everywhere. A range-analysis pass elides checks proven safe. Tests:
   - out-of-bounds code traps with a precise diagnostic;
   - the bench suite is ≤ 5% slower with checks on;
   - the elision count is reported.
   - *Status: done (freestanding/kernel backend).* Spelled `slice[T]` instead of `[]T` so frozen grammar v1.1 (a subscript expression) is unchanged. A slice is a 16-byte (ptr, len) value: `slice(p, n)`, `x[a:b]` / `x[:b]` / `x[a:]` on arrays and slices (checked 0 ≤ a ≤ b ≤ len), `len(x)` (constant for arrays), slice parameters passed in two registers, copy-on-assign; returning a slice/struct/array is a compile error for now. Every array and slice index is checked (unsigned compare, so negative indices fail); a failure calls `forge_bounds_fail(line, idx, len, file)` with the *original* file:line (fs_include now keeps an expanded-line map), then `ud2` (bare `ud2` when no handler exists). tests/fs/linux.cudi prints `bounds check failed: f.cud:5: index 3 out of range for length 3` and exits 134; the kernel panics with the same text. Constant out-of-range array indices are compile errors. Elision: `for v in range(len(x))`, `range(C, len(x))`, `range(K)` (literal or named constant K ≤ array length, literal C ≥ 0, positive step) drop the check on `x[v]` when the body never assigns or takes `addr()` of v or x. Since 2026-11-24 a once-written `n = len(x)` local (x a slice parameter never written) stands for `len(x)`, `while v < n:` / `while v < len(x):` (v unsigned, no `addr(v)` in the function) elides `x[v]` in that loop's own body until v is written, and `x[v - K]` in `range(C, ...)` is elided for literal K ≤ C; the bench went from 17 sites / 13 checked to 9 checked (its sieve has no check left, about 6.4M to 1M dynamic checks per round). `--bounds-stats` prints `bounds: S sites, C checked, E elided`; the kernel is 278 sites, 177 checked, 101 elided. `--no-bounds` / `# cuditor: no-bounds-checks` turn checks off for measurement. tests/bounds/run.sh (20 checks, in run_tests.sh): 3 traps with exact diagnostics, 2 compile-fail cases, bare ud2, the elision count, flag/pragma off, and a sieve/histogram/prefix-sum bench that must be ≤ 5% slower checked; measured ~0–4%. (The bench was best of 5, then best of 7, then best of 21 per variant; since inv156 it is the median of 21 pair ratios, each pair the best of 3 interleaved rounds per variant, after best-of comparisons failed under gate load with identical code in inv138 and inv156.) The checks found a real kernel bug: kexec quiesce called `ioapic_mask(i)` for i up to 23, reading past the 16-entry `irq_gsi` table; it now masks IOAPIC pins directly (`ioapic_mask_pin`). Gaps: the hosted (GC runtime) backend already bounds-checks lists and strings at runtime and has no slice type; `ptr[T]` indexing is still unchecked (item 3 makes it `unsafe`); elision is syntactic (no general range analysis; `while` loops only through the `v < n` guard above).
2. **No null:** `ptr[T]` is non-null, and `?ptr[T]` must be checked before use. Test: compile-fail cases, and the kernel compiles with zero unchecked nullables.
   - *Status: done (freestanding/kernel backend).* Spelled `nptr[T]` instead of `?ptr[T]` (the lexer has no `?`; grammar v1.1 unchanged). `ptr[T]` can no longer hold null: a literal `0` or an `nptr[T]` value converting to `ptr[T]` (assignment, argument, return, field store) is a compile error; a `ptr[T]` local needs an initializer and a `ptr[T]` global a non-null one. Indexing or field access through an `nptr[T]` is an error until it is narrowed. Flow-sensitive narrowing for locals/params: `if x != 0:` / `if x:` / `u64(x) != 0` (also as top-level `and` conjuncts) narrow inside the body; `a and b` / `x == 0 or b` narrow while compiling b; `if x == 0:` / `if not x:` whose block ends in return/break/continue/panic (no elif/else) narrows x for the rest of the block; a store of a proven non-null value narrows, any other store clears; leaving a block keeps only facts true on entry and still true; entering a `while`/`for` drops facts for locals the loop assigns. Globals are never narrowed (copy to a local first). Kernel: nullable returns are now `nptr` (`mod_load`, `mod_fail`, `proc_find_l`, `fd_get`, `proc_spawn[_args]`, `blkd_start`, `blkd_spawn`, `kx_restore`, globals `mod_err`/`mod_err_sym`); every caller checks, and self-tests use panicking `proc_spawn_ok` / `mod_load_ok`. This found a real unchecked case: module_test reloaded hello.ko and dereferenced the result without checking it. The EFI loader's `con`/`bs` globals are `nptr` behind `con_out()` / `bsfn()`. The kernel, loader, user programs and modules all compile with zero unchecked nullables. Compile errors now report the original file:line through `include`. tests/nonnull/run.sh (14 checks, in run_tests.sh): a runtime program (linked list walk, and/or/early-exit narrowing) and 13 compile-fail cases. Gaps: explicit int→pointer casts (`ptr[T](0)`) still bypass the check (item 3 confines them to `unsafe:`); zero-initialised structs/arrays with `ptr[T]` fields are not checked; `addr()` of an nptr local does not invalidate its narrowing; narrowing does not follow `while x == 0:` exits or `elif` chains.
3. **`unsafe:` blocks:** raw `vload/vstore`, int→pointer casts, inline asm, and MMIO are allowed only inside them. A `cuditor verify --unsafe-report` lists every block. Test: the counts are tracked in CI, and the kernel's unsafe surface shrinks over time.
   - *Status: done (freestanding/kernel backend).* Spelled `with unsafe:` (parses as a frozen-grammar v1.1 `with` statement) plus a function decorator `@unsafe`; `naked` functions are implicitly unsafe. Outside an unsafe region these are compile errors (`X is unsafe: put it in a `with unsafe:` block or mark the function @unsafe`): `asm`, `load*/store*/vload*/vstore*`, port `in*/out*`, `call_ptr`, `call_efi`, `memcpy`/`memset`, `lgdt/lidt/ltr/invlpg/wrmsr/rdmsr/cli/sti/hlt/wbinvd`, all raw-address `atomic_*`, explicit `ptr[T](int)` / `nptr[T](int)` casts, implicit int→pointer conversion (literal 0 into `nptr` stays safe), `nptr`→`ptr` casts, pointer casts that change the element type, and `ptr[T]` indexing other than `p[0]` (use a slice). This closes the 4.2 gap: `ptr[T](0)` is now always an error, even in unsafe code (4 kernel `return ptr[X](0)` sites became `return 0` from nptr functions; module.cudi's `err` became `nptr[u8]`). `cudc --unsafe-report` lists every region (`unsafe: FILE:LINE fn|naked fn|block in F ops=N`, top-level asm) and a summary; `--unsafe-fix` lists the functions that need `@unsafe` (used once to migrate 213 functions mechanically); `tools/cud_verify.sh --unsafe-report` adds an `unsafe` check with the summary. Current surface: kernel 178 of 327 functions, 758 ops, 7 top-level asm blocks; EFI loader 12 functions/82 ops; user programs 6–8 functions each (the linux syscall shims); modules 0–3. tests/unsafe/run.sh (29 checks, in run_tests.sh): a runtime program using a block and an @unsafe function, 10 compile-fail cases (including `ptr[T](0)` inside @unsafe), and `baseline.txt`, which fails CI if any program's function/block/op/asm count grows. Gaps: unsafety is mostly function-granular after the mechanical migration (shrinking it to blocks is follow-up work); hosted (GC) code has no unsafe operations to gate; struct-pointer field access is not considered unsafe (the pointer is already non-null and typed). Implicit pointer conversions between different element types (`ptr[A]` where `ptr[B]` is expected, in assignments, arguments and returns) are compile errors (`pointer type mismatch: got ptr[ptr[B32]], expected ptr[B32]`, with a hint for `addr()` of a pointer); before, `addr(p)` on a `ptr[T]` parameter passed silently as a `ptr[T]` and produced a wrong Ed25519 public key in cudseal. Regressions: tests/errors/bad_addr_ptr_arg.cud, bad_ptr_elem_assign.cud. No existing freestanding source (128 files: kernel, EFI loader, user, modules, tools, tests) relied on it; their assembly and unsafe reports are unchanged.
4. **Ownership and borrowing** (affine `own T`, `&T` and `&mut T` scoped borrows, regions for arenas and kernel per-request memory). Tests: compile-fail tests for use-after-free, double free, and aliasing a `&mut`. The user programs and shell compile in safe mode.
   - *Status: done (freestanding/kernel backend).* Spelled `own[T]`, `ref[T]`, `mut[T]` (frozen grammar v1.1 has no `&`); all three are non-null pointers. `own[T]` is affine: a whole-value use (assignment, argument, return) moves it, and any later use is `use of moved value `b` (moved at FILE:LINE)`, which covers use-after-free (`free(b)` then `b.v`) and double free; moving or assigning while borrowed, and overwriting a still-live own (it would leak), are errors. `borrow(x)` gives a `ref[T]`, `borrow_mut(x)` a `mut[T]` of an own local x. Inside call arguments the borrow lasts for the call; at statement level it can only initialize a new local and lasts until the end of the block that declares it (lexical, not NLL). Rules: many `ref` or one `mut`; while a `mut` is live the owner is unusable, so `f(m, borrow(m))` is rejected (aliasing a mut); stores through a `ref` are errors; a `mut[T]` cannot be copied; copying a `ref` keeps the owner borrowed; `mut`→`ref` converts implicitly; raw `ptr`↔own/ref/mut conversions and casts are unsafe ops; own→ref/mut without borrow() is an error. Moves are flow-sensitive: `if`/`elif`/`else` join the moved states of branches that fall through; a loop that moves an outer own value (at the end of the body or a `continue`) is an error. Restrictions: no own/ref/mut globals; direct `own[T]` fields on local structs have definite initialisation, move-out, reinitialisation and per-field lexical borrows (Stage 2); by-value owner-bearing structs, nested owner-bearing structs and globals/arrays of such structs are refused; no ref/mut returns (no lifetimes). `slice(p, n)` over a raw pointer is now an unsafe op. Safe mode: `# cuditor: safe` makes any `@unsafe` function, `with unsafe:` block or top-level asm in the main file an error (included libraries are the trusted base). sh, bg, forktest, hello, cat, sum and crash are safe-mode programs; raw memory goes through four trusted `ulib.cudi` helpers (`mem_get8/set8/get64/set64`), sh parses dirents with array indexing. Only blkd (a driver) and fault (deliberate fault) keep unsafe code. tests/own/run.sh (19 checks, in run_tests.sh): a runtime program and 18 compile-fail cases (use after move, use after free, double free, aliasing a mut, borrow while mut-borrowed, mut while shared, store through ref, move while borrowed, move in loop, move in one branch, leaking reassign, dead borrow, borrow into an existing variable, mut copy, own as ref, raw→own, borrow return, safe mode). Gaps: affine not linear (dropping an own field without freeing is not detected); kernel data structures have not yet been converted; regions/arenas not done; borrows are lexical. *Fix (2026-11-13):* `addr()` of an own/ref/mut value (a local or an own field) was allowed in safe code and gave a `ptr[own[T]]` whose `p[0]` handed out a second owner; it is now an unsafe operation (tests/own/bad_addr_owner.cud, bad_field_addr.cud). *Fix (2026-11-13):* the struct-field check looked only at the field's own type, so arrays and slices of owners at any depth (`own[T][N]`, `own[T][2][3]`, `slice[own[T]]`) were accepted as fields and `q.a[0]` could be copied into two owners with no error; such fields are now refused ("arrays/slices of own/ref/mut struct fields need per-element move tracking"; tests/own/bad_field_own_{array,nested,slice}.cud, tests/own now 22 checks). *Fix (2026-11-13, found reviewing Stage 3a):* that check covered only struct fields: a global, local or parameter `own[T][N]` (and `ref`/`mut` arrays, `slice[own[T]]`, `slice(p, n)` over a `ptr[own[T]]`) still compiled, so `a = ns[0]; b = ns[0]` gave two owners of one object in safe code, and a global array of owners starts as null owners. `fs_type` now refuses any array or slice whose element (at any depth) is own/ref/mut, and so does the `slice()` intrinsic ("arrays/slices of own/ref/mut need per-element move tracking"; the struct-field check is folded into it). Five new compile-fail tests (bad_arr_own_global, bad_arr_own_local, bad_arr_ref_param, bad_slice_own_local, bad_slice_own_intrin; all five compiled on 1d4e26e); tests/own 55 checks. Arrays of owners come back with `nown[T]` and per-element `take`/`replace` (Stage 3). *Fix (2026-11-13, found reviewing Stage 3a):* `addr()` of a place reached through a `ref[T]` (`addr(p.id)`, `addr(p.inner.v[2])`, `addr(p[0])`) gave a raw `ptr[T]` in safe code, and `a[0] = v` (or `atomic_store(addr(p.id), ...)`) then wrote through a shared borrow; the pointer also outlives the borrow. `fs_postfix` now records whether a place went through a `ref[T]` dereference (`fs_viaref`) and `addr()` of such a place is an unsafe operation. Through `mut[T]` it stays safe (exclusive and writable). Tests: bad_addr_ref_{field,nested,index,atomic} (all four compiled on 1d4e26e) and addr_paths_ok (mut path safe, ref path in @unsafe, runs); tests/own 60 checks. Unsafe report unchanged (708): no Forge code took such an address. *Fix (2026-11-13, found while testing Stage 3b):* pointer arithmetic on own/ref/mut kept the pointer kind, so `r = q + 8` was a second `own[T]` (or a `ref`/`mut` to the next object) in safe code; it is now an unsafe operation (tests/own/bad_own_arith; it compiled on 1b4a017). *Fix (2026-11-13, found while testing Stage 3b):* a whole-element `p[i]` through a pointer whose element is own/ref/mut read or overwrote that owner with no move tracking (`a = q[0]; b = q[0]` on an `own[own[T]]` or a `ptr[own[T]]` gave two owners in safe code); it is now an unsafe operation, and `q[0].id` is unchanged (tests/own/bad_own_ptr_index, bad_own_ptr_index_store; both compiled on 1b4a017). *Stage 3b-min (2026-11-13):* `nown[T]` (ftsg 5), an own that may be none, for locals, parameters, returns and fields; usable as `own[T]` only under a non-null proof (build-plan item 2).
5. **Generics** (monomorphized) and `defer`. Stdlib containers become generic: `Vec[T]`, `Map[K,V]`.
   - *Status (defer, 4.5a): done (freestanding).* Spelled `with defer:` (a frozen-grammar v1.1 `with` statement). The block must be at the top level of a function body; it is registered when reached and re-emitted, newest first, before every later `return` (after the return value is computed; %rax is preserved) and at a fall-through function end. It cannot contain `return`, `break`/`continue` or another defer. Block-scoped borrows end before the defers run; ownership is checked on each emitted path, so `with defer: free(b)` followed by an explicit `free(b)` is a use of a moved value. `panic` does not run defers. tests/defer/run.sh (5 checks): LIFO order across early return / break / fall-through and 4 compile-fail cases.
   - *Status (generics, 4.5b): done (freestanding).* `@generic(T, ...)` decorates a `def` or `struct` (frozen grammar: decorator + `Name[T]` subscript types). Monomorphized on demand: each distinct type tuple gets one instance (struct type `Pair[u64]`; function symbol `name__g<N>`), type-checked with the parameters bound to concrete types, so all ownership/bounds/unsafe rules apply per instance. Calls are `f[T](...)` or inferred `f(...)` (unification over ptr/nptr/slice/own/ref/mut and generic struct arguments; literal-only params default to i64; otherwise "cannot infer type parameter"). `T(x)` casts and `sizeof(T)` work on bound params. No trait bounds: an instance that misuses T fails when instantiated. Generic functions cannot have their address taken. tests/generic/run.sh (5 checks).
   - *Status (Vec/Map, 4.5c): done (freestanding stdlib).* std/vec.cudi (`Vec[T]`: vec_init/reserve/push/get/set/pop/len/free) and std/map.cudi (`Map[K, V]`, open addressing + tombstones, integer-like keys: map_init/put/get/has/del/len/free) are generic, trusted `@unsafe` library code over an includer-provided `forge_alloc(bytes) -> u64` / `forge_free(p, bytes)`; callers stay in safe code (`vec_push(addr(v), x)`). vec_get/vec_set index through `slice(data, len)`, so out-of-range access traps via forge_bounds_fail. Not yet used by the kernel (it has no general-purpose heap API wired to forge_alloc); keys are compared with `==` (no user hash/eq). tests/generic: std.cud (Vec[u64], Vec[u8], Map[u64,u32] with growth/delete, alloc/free balance) and oob.cud (trap).
6. **Weaker atomics orderings** (acquire/release).
   - *Status (4.6): done (freestanding/kernel backend).* Typed, safe atomics with an explicit ordering word: `atomic_load(p, o)`, `atomic_store(p, v, o)`, `atomic_swap(p, v, o)`, `atomic_fetch_add(p, v, o)`, `atomic_cas(p, expected, new, o)` (returns the old value) and `atomic_fence(o)`, where `p` is a non-null `ptr[T]`/`own`/`mut` (loads also accept `ref[T]`) to an integer of 1/2/4/8 bytes and `o` is `relaxed|acquire|release|acq_rel|seq_cst`. Invalid combinations are compile errors (release/acq_rel loads, acquire/acq_rel stores, relaxed fence). x86-64 TSO lowering: loads and relaxed/release stores are plain `mov`, seq_cst stores `xchg`, RMW ops `lock`-prefixed, `atomic_fence(seq_cst)` = `mfence` (other fences are compiler-only; the backend does not reorder memory accesses). Usable from `# cuditor: safe` code; the raw-address `atomic_*32/64` intrinsics remain and stay unsafe. tests/atomic/run.sh (8 checks: safe-mode publish/consume + RMW semantics, codegen mapping, 6 compile-fail cases). Gap: the kernel still uses the raw intrinsics (migration to typed atomics is follow-up); only x86-64 is targeted, so weaker orderings do not yet produce cheaper code than seq_cst except for stores.
   - *Status (post-Phase-4 cleanup): done.* All 66 raw-address `atomic_*64` sites in the kernel became typed atomics (`atomic_fetch_add(addr(x), 1, acq_rel)`, `atomic_load(..., acquire)`, `atomic_store(..., seq_cst)`; identical x86 code), and `spin_lock`/`spin_unlock` take `ptr[u64]` and are safe (swap-acquire / store-release; 168 call sites rewritten). `@unsafe` was then stripped from every kernel function and re-applied only where `--unsafe-fix` reports an unsafe op. Kernel unsafe surface: 178 functions / 758 ops -> 163 / 692 for the kernel's own code; 171 / 734 including the 8 trusted std/vec+map instances now compiled in (baseline.txt updated to 171 0 734 7). The kernel provides `forge_alloc`/`forge_free` over kmalloc/kfree and `vecmap_test` (boot log: `generic Vec/Map OK`, heap leaked 0) exercises `Vec[u64]` past a page and `Map[u64, u64]` with deletes.

## Phase 5 — Capability OS and sandboxing
*Pillars: A, D.*
1. **Handles replace ambient authority.** Every fd/proc/memory object is a capability with rights bits. Syscalls check rights, `dup` can only narrow them, and capabilities pass over IPC channels. Test: a child given a read-only handle cannot write; no global path lookup is possible without a directory capability.
   - *Status: done for file handles (console, files, directories).* Each fd carries rights (READ, WRITE, LOOKUP, DUP, XFER). read/getdents need READ and write needs WRITE. `dup(fd, rights)` (420) needs DUP and fails with EPERM unless the new rights are a subset. `openat(dirfd, path)` (421) needs LOOKUP and rejects absolute paths and `.`/`..`. `rights(fd)` is 422. open, stat and exec resolve only through the root-directory capability at fd 3; without it they return EACCES and the kernel logs `cap: pid N denied ...`. Rights survive fork and kexec, packed into the high half of the handoff fd slot. Test: `captest`, run by the boot shell script. Process and memory handles, and passing capabilities over IPC, come in 5.2.
2. **IPC channels** carry messages plus handles, with wait queues. Test: ping-pong latency is measured, and a handle is transferred.
   - *Status: done.* `chan(fds)` (423) creates two endpoint handles. `send(fd, buf, n, h)` (424) needs WRITE on the endpoint and XFER on h. `recv(fd, buf, n, &h)` (425) needs READ. A message holds 1–64 bytes plus an optional handle. The handle is moved, so the sender loses it and the receiver gets it in a free fd with the same rights. Each direction is a 16-slot ring; receivers and senders block on wait queues. recv returns 0 (EOF) once the peer's end is closed and the ring is empty. Channels come from a static 16-entry table, so none of the code needs `unsafe` beyond what the kernel already had. kexec refuses to run while any channel is open. Test: `chantest` does 2000 ping-pong round trips (about 9 ticks at 100 Hz under QEMU TCG, roughly 45 µs per round trip), refuses a handle without XFER, moves a file handle that the child reads but cannot write and echoes, and checks EOF after the child exits.
3. **Per-app sandboxes:** a manifest declares the capabilities an app gets (dirs, devices, network). The shell launches apps through the manifest. Test: an app that reaches outside its manifest is denied and logged.
   - *Status: done (files and dirs; no device or network grants yet, since there are no such handle types).* `sh: run APP [args]` reads `\EFI\Incudela\apps\APP.mf`. Each `read PATH` line becomes a READ|DUP handle and each `dir PATH` line a READ|LOOKUP|DUP handle, on fds 4.. in manifest order; rights are narrowed in place with `restrict` (427). The shell then calls `exec_sandboxed` (426), which drops the root capability (fd 3) and marks the process sandboxed; its forked children inherit that. Each open, stat or exec outside the manifest returns EACCES and the kernel logs `sandbox: pid N (APP) denied OP PATH: not in its manifest`. kexec refuses while a sandboxed process is alive. Test: `run sbtest` reads its granted file (write and widening denied) and looks up inside its granted dir (`..` denied); open, stat and exec outside the manifest are denied and logged.
4. **Kernel hardening:** KASLR, stack canaries, guard pages per thread, and W^X for user ELF (already enforced for the kernel).
   - *Status: 5.4a (user W^X) done.* The ELF loader refuses any PT_LOAD that is both writable and executable, and refuses segments with different W/NX permissions that share a page (before, the first segment's flags silently won). Non-text segments, the stack, brk and mmap are NX. Test: the kernel feeds the loader a crafted RWX image and a mixed RX/RW page image (both refused, counted in `elf_wx_rejects`); `wxtest` forks children that execute data, mmap and stack memory and write their own text, and each dies with #PF (exit 0x10e). Guard pages, canaries and KASLR follow.
   - *Status: 5.4b (per-thread guard pages) done.* Kernel thread stacks (4 pages) come from `kstack_alloc` in their own bump VA range (`KSTACKS_BASE`, never reused) with an unmapped guard page below each. A thread that overflows faults on the guard page; the #PF cannot be pushed, so #DF (IST1) checks CR2 against the current thread's guard page and restarts the thread at `thread_overflow_exit` on the top of its own stack, which logs and exits it. Test: `guard_test` spawns an unbounded recursion thread; it is killed, the counter moves by 1, and all its frames come back.
   - *Status: 5.4c (stack canaries) done.* The freestanding compiler honours `# cuditor: stack-protector`: every function with a local or parameter wider than a word (array, struct) stores `stack_canary` at -8(%rbp) on entry and checks it before `leave`, calling `stack_smashed` on mismatch (33 kernel functions). The kernel seeds the canary from the TSC at the start of `kmain_high` (low byte zero). Test: `canary_test` runs a thread that copies 32 bytes past a 128-byte local buffer; the epilogue check catches it, the thread is killed and the kernel carries on.
   - *Status: 5.4d (KASLR) partial.* The dynamic kernel regions are randomized per boot: the big heap and the thread-stack range each start at a random 2 MiB slot (16 bits of entropy each, TSC-seeded in `canary_init`). The kernel image, the boot stack/IST stacks, the HHDM and the demand region stay fixed: moving the image needs a position-independent kernel plus relocation support in both loaders (GRUB multiboot2 and the Incudela UEFI loader) and in kexec. Test: `os/kaslr` requires at least 5 distinct layouts across the 6 boots in tests/os/run.sh (3 first-generation kernels + 3 kexec'd ones).
   - *Status: 5.4e (image KASLR) done.* The kernel image itself now moves. It was already nearly position-independent (the freestanding backend emits RIP-relative addressing for symbols); the build links once with `ld -q`, `tools/krel.py` turns the remaining relocations (R_X86_64_64/32S into the high half, PC32 from the high half to the low boot stub) into a `.krel` table appended as the last segment, and the final image is linked without ELF relocation sections (GRUB refuses those). The kernel self-relocates, so the same mechanism serves GRUB (BIOS and UEFI), the Incudela UEFI loader and kexec: `kaslr_pick` chooses a 2 MiB slide (about 500 slots, TSC-seeded, above the image size and below the fixed stacks at -1 GiB), `paging_init` maps the image at both KBASE and KBASE+slide, `krel_apply` patches it through the HHDM, `switch_stack` continues in the slid alias and `kaslr_unmap` drops the link-address alias. The Incudela UEFI loader and kexec read the table bounds from the extended FORGEKRN header and refuse kernels without one. Test: `os/kaslr` also requires at least 5 distinct image bases over the 6 boots, the unslid alias unmapped in all 6, and the loader and the 3 kexecs reporting a relocatable kernel.

## Phase 6 — Proven-safe programs only (signature feature 2)
- The loader accepts only images produced by the Forge verifier: a signed proof manifest stating the safety level (no unchecked unsafe, or an audited unsafe list) and the declared capabilities.
  - **6.1 status: done.** `tools/cudseal.py` runs `cudc --unsafe-report` and seals only programs whose unsafe counts are zero or within `tests/unsafe/baseline.txt`; declared caps come from `# cuditor: caps(...)`. The 128-byte trailer holds level, unsafe ops, caps, the ELF SHA-256 and an HMAC-SHA256 under a per-build key (`build/user/seal.key`, embedded in the kernel). `image_verify` (seal.cudi) runs in `sys_exec` and `proc_spawn_args`; boot self-test: hello/cat/fault accepted with caps 0/fs/probe; unsealed, tampered and forged images refused for the right reason. Gap closed (6.5): the seal is now an Ed25519 signature (see below). .ko modules are sealed too (6.6).
- The kernel grants exactly the declared capabilities and nothing else.
  - **6.2 status: done.** `Proc.caps` is set from the verified manifest (spawn: declared; exec: declared ∩ current; fork inherits; kexec carries it in record word +56, handoff format v3). `syscall_dispatch` maps each syscall to a cap (fs 2/4/78/421, spawn 57/59/61/426, ipc 423-425, drv 400-407, ktest 408, kexec 409, probe 200; the rest are base) and refuses with EACCES + a `caps: pid N denied syscall NR` log. ktest_hooks gating of 408/409 is unchanged and applies on top. Self-test: `capdeny` (caps(fs)) opens a file, fork and probe are denied.
- Test: an unverified or tampered ELF is refused. A verified program that tries an undeclared capability is denied at the syscall boundary.
- The Linux ABI layer (Phase 11) runs only inside an explicit compatibility sandbox.
  - **6.3 status: done.** End-to-end through the shell (tests/os/boot.py): `unsealed`, `tampered`, `forged` and `linuxabi` are each refused by `sys_exec` with their reason logged (`verify: /efi/incudela/bin/X refused: ...`, sh reports exit 127), and `capdeny` runs with caps(fs) only: fork and probe are denied with EACCES at the syscall gate. Markers checked in tests/os/run.sh.
  - **6.4 status: done (gate only; Phase 11 not built).** `image_verify` refuses any image tagged EI_OSABI = 3 (Linux) with reason 6 even when correctly sealed, unless `compat_sandbox_ready` is set; only the Phase 11 compat sandbox may set it (11.1a: `lx_init` sets it, and a Linux image additionally needs a sandboxed launch). Test: `linuxabi` (hello re-tagged and resealed) is refused at boot self-test and from sh. Gap: Linux binaries tagged OSABI 0 (most static musl builds) are caught only because they are unsealed; Phase 11 must add explicit ABI detection.
  - **6.5 (gap) status: done.** Seal v2: the 160-byte trailer carries an Ed25519 signature (R || S at +96) over trailer[0:96] instead of the HMAC. `tools/ed25519.py` signs at build time with the per-tree seed `build/user/seal.key`; the kernel embeds only `seal.pub` and verifies with `examples/kernel/ed25519.cudi` (a fully safe TweetNaCl-style port: SHA-512, GF(2^255-19) in 16-bit limbs, canonical-S check). Tests: tests/ed25519/run.sh checks 12 vectors made by `cryptography` (6 valid, R/S/message flips, non-canonical S, wrong key, non-point key) at O2 and O0; os/seal-private-key-not-shipped checks the seed is absent from kernel.elf and the disk image while the public key is present; the boot and shell refusals are unchanged (forged manifest -> bad signature).
  - **6.6 (gap) status: done.** Kernel modules are sealed with `cudseal.py --module` (trailer word +56 = 1, so a sealed user program is not a valid module and vice versa). `mod_load` verifies the seal before parsing the ELF, so every path that loads code into the kernel (boot module test, live patch, tty hot swap) refuses unsealed, tampered or wrong-kind images. Verified trailer contents are cached (8 entries) so repeat loads skip the Ed25519 step; the image SHA-256 is still recomputed on every load. Tests: unsealed.ko, tampered.ko and userimg.ko rejected with their reasons (7 rejects total); hot swap to an unsealed tty1u.ko is refused and the running line discipline stays installed; the 1000-cycle load/unload leak test still passes.

## Phase 7 — Own toolchain
*Pillars: C, F. Closes SYSTEMS.md item 7.*
1. Built-in x86-64 assembler. Test: it is byte-identical to GNU `as` for all compiler output and the kernel asm blocks.
   - *Status: done.* `tools/fas.cud` (built to `build/fas`; `fas [-I dir] [-o out.o] in.s`) is an AT&T-syntax assembler for the subset cudc, the kernel, the EFI loader, modules and user programs emit: GPR/ALU/shift/mul/div, control and segment registers, moffs/movabs, SSE/SSE2 scalar+packed and conversions, x87, system instructions, `.code16/.code32/.code64`, sections with flags/types, data/fill/align/incbin/set directives, numeric local labels. It reproduces GNU as's object layout exactly: section order and file-offset alignment, BFD symbol ordering and suffix-merged strtab, section-symbol relocations for locals, PC32 vs PLT32 (PC32 when a call target is a defined local at the point of the call, even if made global/weak later), and GNU's jump relaxation (in-order passes, forward targets estimated as old address + stretch, with no positive stretch across an alignment region). Values in the typed-int trap band (2^62..2^62+3) are carried as sentinels. Test: tests/fas/run.sh (in run_tests.sh, so at O2 and O0): every tests/*.cud and tests/runtime/*.cud program, the compiler (6 MB of asm), fas itself, every user/EFI/module asm file, kernel.s and kernel-next.s (with their asm blocks) and the krel stubs assemble byte-identical to GNU as (`cmp` of the .o), plus edge cases (-2^63 immediate, 2 GiB .bss). Gaps: `.type/.size/.ident/.file` and instructions outside that subset are rejected with an error rather than supported; the literal values -8070450532247928817..-8070450532247928820 collide with the band sentinel; fas is about 14× slower than GNU as on the 6 MB compiler output (2.5 s vs 0.18 s); the build used GNU as until item 2 switched it.
2. ELF64 and PE32+ writer and linker, plus linker-script equivalents. Test: the kernel, the EFI loader, and user programs build with no `as`, `ld`, or `objcopy`, and all boot tests pass.
   - *Status: done.* `tools/fld.cud` (built to `build/fld`; `fld [--format exec|kernel|pe] [--base A] [-e SYM] [--subsystem N] -o out in.o...`) links ELF64 relocatable objects (R_X86_64_64/32/32S/16/8/PC32/PLT32/PC16/PC8, RELA only, globals/weaks/locals, weak undefined = 0, duplicate and undefined symbols diagnosed). `exec` reproduces GNU ld's default static layout (R header page, RX .text, R .rodata, RW .data/.bss at DATA_SEGMENT_ALIGN, GNU_STACK RW, `--base` = `-Ttext-segment`); `kernel` is the built-in equivalent of examples/kernel/linker.ld (boot stub + bootdata/bootbss at 1 MiB, .text/.rodata/.data+.bss at -2 GiB + phys with paddr = vaddr - KBASE, W^X PT_LOADs, the `__text_*`/`__rodata_*`/`__data_*`/`__krel_*`/`__kernel_phys_*` symbols) and writes the image-KASLR `.krel` table itself from the relocations it applies, replacing the ld -q / tools/krel.py / as / second-link sequence; `pe` writes a PE32+ EFI application (.text RX, .rdata R, .data RW with .bss as uninitialised tail, DIR64 base relocations for any R_X86_64_64, NX/dynamic-base/high-entropy). Every build and test script now uses build/fas + build/fld (forge, run_tests.sh, tests/*, tools/cud_test.sh, tools/cud_verify.sh, examples/{user,modules,kernel,efi}/build.sh); no objcopy was in use. build.sh: the binutils seed is stage2 (from the Rust bootstrap's stage1) plus stage2-built fas/fld; stage3 and stage4 are assembled and linked by fas/fld, then fas/fld are rebuilt by the fixpoint compiler and themselves and must reproduce stage3's .o and executable byte-for-byte (`TOOLS OK`). Test: tests/fld/run.sh (in run_tests.sh): fld output loads byte-identical segments at identical addresses with the same entry as GNU ld's for the compiler (which then reproduces stage3.s), every tests/*.cud program, every user program, and kernel/kernel-next against linker.ld + krel.py (same 15-entry .krel); the PE image passes structural checks (W^X sections, entry in code, alignment); undefined/duplicate symbol diagnostics; and tests/os (7 PASS: BIOS, UEFI GRUB, the fld-linked Forge EFI loader on GPT, kexec, KASLR) boots only fld-linked images. Gaps: the Rust bootstrap (src/main.rs) and the stage2/fas/fld seed still call binutils, so a binutils-free bootstrap needs a committed seed binary; PE output was validated by booting in OVMF and structurally, not against ld's PE layout (ld's .idata stub is not reproduced and not needed); `.eh_frame` from gcc objects is dropped; no COMMON symbols, no REL (non-RELA) input, no dynamic linking, no section GC.
3. DWARF line tables. Test: gdb on the QEMU gdbstub breaks at `schedule` and shows Forge source lines.
   - *Status: done.* `cudc -g` (freestanding path) emits DWARF 4: `.debug_abbrev`, `.debug_info` (one CU, a subprogram per function with name/decl_file/decl_line/low_pc/high_pc), `.debug_ranges`, and `.debug_line` with a sequence per function and a row per statement, mapped through the include expansion back to the real file and line (e.g. `sched.cudi:159`). fld concatenates `.debug_*` sections as non-alloc output (absolute relocations against debug sections resolve at section offset 0; no krel entries), so the loaded image is byte-identical with and without `-g`. Test: tests/dwarf/run.sh (run from tests/os/run.sh): the image-unchanged check, readelf decodes the line table, and gdb attached to a QEMU boot of the `-g` kernel (`symbol-file -o <KASLR slide>`) hits `hbreak schedule` and shows `sched.cudi:159  spin_lock(addr(rq_lock))`. Gaps: line info only (no variables, types or call-frame info, so `bt` past one frame and `print` of locals do not work); only the kernel build uses `-g`; hosted programs ignore it; gdb must be built with XML support (the box uses conda `defaults` gdb 16.3 at ~/gdbd because the Debian mirror is down and conda-forge gdb lacks expat).
4. Package manager: `cuditor.toml`, a content-hashed lockfile, and a local registry directory. Test: a reproducible build gives the same hash twice.
   - *Status: done.* `cuditor pkg [--registry DIR] lock | build [-o OUT] | sha256 FILE...` (tools/pkg.cud, built to build/pkg on demand; registry defaults to $FORGE_REGISTRY, else ./registry). cuditor.toml has `[package]` (name, version, main, files) and `[dependencies]` (exact `1.2.0`, caret `^1.2`, or `*`). The registry is a local directory: `<name>/versions` plus `<name>/<version>/{cuditor.toml,files}`. `lock` resolves by depth-first search with backtracking (newest compatible version first, one version per package) and writes cuditor.lock: per package its version, direct dependencies and a SHA-256 (implemented in Forge) over cuditor.toml and every file (name, length, bytes), plus the root requirements and a content hash. `build` refuses a lock that is stale relative to cuditor.toml, edited, or whose packages no longer hash the same, then stages the project and dependency modules into target/stage (refusing two packages that provide the same module), compiles with cudc/fas/fld and prints the binary's sha256. Test: tests/pkg/run.sh (12 checks, in run_tests.sh): SHA-256 equals sha256sum (incl. high bytes and empty input), resolution picks the newest compatible versions, the package hash matches an independent Python computation, lock is byte-identical when re-run, two clean builds and a build of a copy in another directory give the same binary hash, the program runs, tampered registry / edited lock / stale lock / unsatisfiable requirement / module clash are refused, and an exact pin backtracks a dependent to an older compatible version. (Since item 6 batch 1, 2026-11-23, `<name>/versions` is replaced by the signed `<name>/index`; see that item.) Gaps: local registry only (no fetching; publishing and signatures came with item 6 batch 1); flat module namespace (a dependency's modules are imported by file name); hosted programs only (the kernel does not use packages); TOML subset (strings and string lists in two sections); no dev-dependencies or features.
5. LSP server (diagnostics, goto-definition, hover) built on the JSON AST. Test: scripted LSP sessions.
   - *Status: done.* `cuditor lsp` (tools/lsp.cud, built to build/lsp on demand) speaks JSON-RPC with Content-Length framing on stdio (hand-written JSON parser/serializer in Forge). Capabilities: full text sync, definitionProvider, hoverProvider. On didOpen/didChange/didSave it runs `cudc --emit=ast-json --diagnostics=json` (parse only) and, if that is clean, a full compile with `--diagnostics=json`, and publishes the diagnostics as 0-based LSP ranges with severity and code. An unsaved buffer is written to a hidden sibling file so its imports resolve, and the file is removed afterwards. Goto-definition and hover use the JSON AST: parameters, assignments and loop variables in the enclosing functions, then module-level defs, classes and assignments, then `from m import f` and `import m` + `m.f` into sibling modules. Hover shows the def/class header and docstring (plus file:line for another module), or `(parameter) a: int`. The compiler is run via fork/execve/wait4 from Forge; this needed a runtime fix: `rt_syscall` now zeroes r10/r8/r9, because wait4 took a stale r10 as its rusage pointer and overwrote memory. Test: tests/lsp/run.sh (22 checks, in run_tests.sh), a scripted Python client: initialize; a clean file has no diagnostics; a type error (E0302), a syntax error (E0105) and an undefined name (E0201) in the unsaved buffer are reported at the right position, with no temp files left and the disk file untouched; fixing the buffer clears them; definitions of a function, local variable, parameter, loop variable, from-import, module attribute and class (cross-file); a builtin gives null; hover for the signature and docstring, an imported function and a parameter type; an unknown method gives -32601; shutdown/exit gives exit code 0. **Phase 11.3 extension (done):** incremental text sync (`change: 2`, range edits applied in order, full text still accepted); positions on the wire are UTF-16 code units, converted to and from byte columns for diagnostics, definitions, references and requests (`positionEncoding: utf-16`); incremental re-check: a document is recompiled only if its text differs from the last checked text (identical edits and a save of unchanged text republish cached diagnostics), sibling modules are parsed once per on-disk text and cached, and saving a module rechecks the open documents that import it; `forge/stats` reports the compile count so the tests can check this. Attribute resolution: `self.x` / `self.m` in a class (methods, class-level assignments, `self.x =` in any method), and `obj.m` when obj is a parameter annotated with a class (`x: util.Counter`) or a variable assigned `C(...)`, across modules. New: textDocument/references (whole-word occurrences outside strings/comments in the file and its sibling modules, kept only if they resolve to the same definition; includeDeclaration), textDocument/rename (WorkspaceEdit across modules; invalid identifiers give -32602) and textDocument/completion (scope names, parameters and builtins with prefix filtering; module members after `m.`; class members after `self.` / `obj.`; `.` trigger). tests/lsp/run.sh now has 45 checks. Remaining gaps: definition columns are still found by searching the line (the AST has no columns); attributes resolve only through annotations and direct constructor assignments (no type inference of return values); references/rename scan the project directory only and are textual-then-resolved, so they cost one resolve per occurrence; `def f(:` no longer crashes cudc (fixed: an unclosed bracket is reported as E0105 `expected ')' to close '(' (never closed)` at the bracket, before the type checker runs; tests/diag/parse_unclosed_*), but the LSP still runs the full compile only after a clean parse, which is cheaper; diagnostics are still per file (cudc has no incremental mode).

## Phase 8 — Real hardware and storage
*Pillar: F. Closes SYSTEMS.md items 1, 2, and 5.*

**Kernel infrastructure:**
- buddy allocator **(done)**: `mm.cudi` keeps the `frame_bits` used-map authoritative and adds per-order free-block bitmaps (orders 0..10, 4 KiB..4 MiB); blocks are re-validated against `frame_bits` on every take, so direct `frame_bits` edits (kexec grab, boot reserves) leave only stale entries that are dropped; the maps are rebuilt from `frame_bits` once if they run dry. `frame_alloc_contig(n)` takes an order-ceil(log2 n) block below 4 GiB (aligned) and returns its tail; `frame_free` coalesces. Boot test (`buddy_test`, all 3 boot paths and the kexec'd kernels): orders 0..10 come back aligned, 1000- and 3-frame runs work, 3050 frames held, everything coalesces back to the same number of 4 MiB blocks, 0 frames leaked. Gaps: contiguous requests are capped at 4 MiB (1024 frames); no per-CPU page caches; the kexec grab still scans `frame_bits` linearly.
- vmalloc **(done)**: the big kernel heap (`kmalloc` > 4 KiB) takes virtual ranges from a sorted, coalescing first-fit free list (`va_alloc`/`va_free` in `mm.cudi`, 256 slots) instead of only bumping; each range keeps an unmapped guard page. Boot test (`vmalloc_test`): 2000 mixed-size big allocations reuse VA (2000 reuses, high-water +183 pages, 1 free range left), 0 frames leaked. Gaps: list overflow drops a range (VA leak only); no `vmap` of arbitrary frames yet.
- PCID **(done, untested on hardware with PCID)**: `cpux.cudi` gives each address space PCID 1..63 per CPU and reloads CR3 with bit 63 (keep TLB) only if that CPU's slot still belongs to the same PML4. User shootdowns (on every CPU, including ones not running the space), `user_unmap` and `as_free` clear the PML4's slots, so the next load flushes. CR4.PCIDE is set only when CPUID offers it; the kexec stub clears PCIDE with PGE. Boot test: slot bookkeeping (hit, forget, collision) checked on every boot. Gap: QEMU TCG does not offer PCID and /dev/kvm is not accessible here, so the CR3-with-PCID path has not run; with PCID on, the boot panics if no switch ever reused the TLB.
- x2APIC **(done)**: `lapic_init` enables x2APIC (IA32_APIC_BASE bits 10+11) when CPUID.1:ECX[21] is set, on the BSP and every AP. `lapic_rd`/`lapic_wr` keep the xAPIC offsets as their interface and map them to MSRs 0x800+off/16; the ID read is shifted like xAPIC, and the ICR-high write is kept per CPU and merged into the single 64-bit ICR write (MSR 0x830), so callers are unchanged. No delivery-status polling in x2APIC mode. Boot test: x2APIC mode on all CPUs, IPI count via MSR 0x830 (QEMU TCG offers x2APIC). Unsafe ops at the 733 baseline allowance. Gap: APIC ids >= 256 are not handled (ID table is u8[256]).
- HPET/TSC-deadline **(done; TSC-deadline untested)**: `acpi_init` records the HPET block from the ACPI HPET table; `lapic_init` enables the main counter and times 10 ms of it against the TSC (32-bit counters masked), then uses the HPET value for the TSC and LAPIC timer rates (the PIT window is rescaled) and reports whether the PIT calibration agreed within 25% (not fatal: under a loaded emulator host the polled PIT window is skewed, which failed boots at O0). When CPUID.1:ECX[24] is set the LAPIC timer runs in TSC-deadline mode on every CPU: `lapic_wr(0x380, n)` becomes a write of TSC+n LAPIC ticks to IA32_TSC_DEADLINE and the timer handler re-arms it, so callers are unchanged; else LAPIC periodic. Boot test: HPET period line, timer mode line (panics if deadline mode armed fewer than 20 times). Gap: QEMU TCG `-cpu max` does not offer TSC-deadline, so that path has not run. Also reclaimed unsafe ops (PIC init from a table, kexec ELF headers read through `ptr[Phdr]`): kernel unsafe ops 733 -> 719.
- per-CPU run queues and load balancing **(done)**: `sched.cudi` keeps one FIFO per CPU (up to 8). `rq_push` puts a pinned thread on its CPU's queue and any other thread on the shortest queue; `rq_pop` takes from the local queue first and otherwise steals from the longest other queue (`rq_steals` counts). The single `rq_lock` is kept (it is held across `ctx_switch`, which keeps the no-double-run invariant), so this balances load but does not remove lock contention. Boot test: number of queues used and steals printed; panics if more than one CPU is online and fewer than 2 queues were used. Unsafe counts unchanged. Gaps: one global lock; no priorities; no cache-affinity heuristics beyond local-first.
- hardware drivers **(done except GOP console and xHCI mass storage)**: `mmio.cudi` is the only place device registers are touched: `mmio_rd/mmio_wr/pio_rd/pio_wr` (the only `@unsafe` driver functions) check every access against registered windows (`mmio_add`, `pio_add`, `pci_map_bar` maps BARs uncached+NX, `dma_alloc` zeroed DMA pages) and panic on anything outside one; IOAPIC, PCI config and virtio were converted to them, and `drv_died` is no longer `@unsafe` (kernel unsafe ops 719 -> 676 in the counting pass). `pci.cudi` records every function (`pci_find`, `pci_find_id`, `pci_bar` with sizing). NVMe (`nvme.cudi`): admin + one polled I/O queue pair, Identify, READ only. AHCI (`ahci.cudi`): IDENTIFY + READ DMA EXT only (completions on MSI vector 0x54 after IDENTIFY). xHCI (`xhci.cudi`): reset, command ring (No Op), port scan, Enable Slot, Address Device, GET_DESCRIPTOR on EP0; then HID step 1: GET_DESCRIPTOR(configuration) (9 bytes for wTotalLength, then the whole set), a walk of the interface and endpoint descriptors for a HID boot keyboard interface (class 3, subclass 1, protocol 1) and its interrupt IN endpoint, then SET_CONFIGURATION, SET_PROTOCOL(boot) and SET_IDLE(0) as no-data control transfers (`xh_ctrl`); QEMU usb-kbd: `xHCI: HID boot keyboard: interface 0, interrupt IN endpoint 0x81, max packet 8, interval N`. e1000 and legacy virtio-net (`net.cudi`): send one ARP request for 10.0.2.2 and wait for the reply, then ping it: an IPv4 ICMP echo request (id 0x4647, 56 data bytes, RFC 1071 checksums) to the MAC ARP returned, accepted only if the echo reply carries our id, sequence and data with valid IP and ICMP checksums (`e1000: ICMP echo reply from 10.0.2.2: seq 1, 56 data bytes, checksums ok, N us`), then serve UDP echo on 10.0.2.15:7 for up to 20 s: the first datagram with valid IP and UDP checksums (pseudo-header included) goes back with addresses and ports swapped, and ARP requests for 10.0.2.15 are answered meanwhile. Both NICs share one exchange path (`net_send`/`net_recv`/`net_xchg`). No driver issues a write command to a disk. `hw_quiesce` resets all of them before kexec. Boot test `tests/os/drivers.sh`: q35 with nvme, ide-hd on AHCI, qemu-xhci + usb-kbd, e1000, virtio-net on user netdevs, each with a hostfwd UDP port that a host-side sender uses for the echo (`host: e1000 echoed 31 bytes identical on try 1`; restrict=off, since slirp's restricted mode drops guest UDP replies); LBA 0 hashes must match the generated images, both images byte-identical afterwards, 0 out-of-window accesses. Gaps: the NICs are polled (the USB keyboard and NVMe I/O completions use MSI-X, AHCI uses MSI); AHCI completions (2026-11-12): after the polled IDENTIFY the driver enables the controller's single-message PCI MSI (capability 0x05, vector 0x54 -> cpu0), PxIE = DHRS | TFES and GHC.IE; a reader with interrupts on and the scheduler running sleeps on a wait queue until slot 0's CI bit clears, and the handler acknowledges PxIS/IS, records a task file error and wakes it, all under rq_lock (no lost wakeup); early-boot and interrupts-off callers still poll, interrupt remapping keeps it polled (no IRTE yet), and hw_quiesce clears GHC.IE/PxIE before kexec. tests/os/drivers.sh requires `AHCI: interrupt-driven reads OK (8 of 8, ` after 8 more reads (real run: 9 reads, 9 completion interrupts, 9 sleeps); NVMe I/O completions (2026-11-12): the I/O completion queue is created with interrupts enabled (IEN, vector 0) and MSI-X table entry 0 sends vector 0x53 to cpu0; a reader with interrupts on and the scheduler running sleeps on a wait queue until the completion entry's phase flips (checked and woken under rq_lock, so no wakeup is lost), early-boot and interrupts-off callers still poll, admin commands (init only) stay polled, and with interrupt remapping on the driver stays polled (no IRTE for it yet). tests/os/drivers.sh requires `NVMe: interrupt-driven reads OK (8 of 8, ` after 8 more reads (real run: 9 reads, 9 completion interrupts, 9 sleeps); the Incudela FS suite (kernel ffs and the ring-3 nvmed service) runs on the same path; USB HID step 2 (2026-11-12): Configure Endpoint adds the interrupt IN endpoint (DCI 2n+1, Interrupt IN context, CErr 3, interval from bInterval as a 125 us exponent, max ESIT payload = max packet) with its own transfer ring of 8 Normal TRBs (IOC + ISP, one 8-byte buffer each); the output context must show the endpoint running. `xh_kbd_poll` reads transfer events for up to 8 s or until Enter, maps each completion back to its buffer through the TRB pointer, decodes keys absent from the previous report (letters with shift, digits, space, `-`, `.`), and re-queues the TRB. tests/os/drivers.sh adds an HMP monitor and types `forge usb` + Enter with `sendkey` once the kernel says it is waiting; the log must read `typed "forge usb" + Enter`. USB HID step 3 (2026-11-12): after the polled phase the keyboard moves to MSI-X vector 0x52 (table entry 0 -> 0xFEE00000 | APIC ID << 12, IMOD 4000, IMAN.IE, USBCMD.INTE); the `on_xhci` handler acknowledges IMAN/USBSTS.EINT, drains the event ring, decodes each report with the same decoder as the polled path (`xh_kbd_report`) and pushes the keys into the tty with `tty_push_l`, then re-queues the TRB and writes ERDP with EHB. It stays polled when interrupt remapping is on or the controller has no MSI-X. tests/os/drivers.sh types `hello usb` + Enter at the `sh$ ` prompt through the USB keyboard and requires `hello: args = 'usb'`. Next: no USB mass storage; no TCP/IP stack beyond ARP, ICMP echo and UDP echo (no TCP, no sockets API, no IP fragments); not tested on real hardware; kexec with these devices present is not in the test.
- GOP console **(done)**: the UEFI loader walks the GOP mode list, sets 1024x768 RGBX/BGRX when offered (checks the SetMode status, else keeps the firmware mode) and reports the mode count and the chosen mode. The kernel console (`console.cudi`) is double-buffered at the cell level: `con_back` is what the screen should show, `con_front` what was drawn; a character draws only if its cell changes, and a scroll shifts `con_back` and `fb_flush` redraws only differing cells, so the uncached framebuffer is never read back (the old memcpy/memset scroll is gone). Boot test: before KERNEL OK the kernel checks back == front and that scrolling drew fewer cells than full redraws would (about 48% in practice), and the boot harness (`tests/os/boot.cud`, ported from boot.py) decodes the QEMU screendump and requires that line on the row directly above KERNEL OK on all three boot paths. After KERNEL OK it issues QEMU monitor `stop`, dumps, then queues `q` and `cont`s, so a host suspend cannot expire the kernel's 5 s `rdtsc` wait mid-dump (inv236 `os/bootpol-config-strict`; inv237). New check `os/boot-harness-delay-after-ok` (6 s delay, FAILs on the pre-stop harness). A failed screendump still FAILs. Gaps: no mode setting from the kernel (BIOS path uses GRUB's VBE mode); no colours or cursor; no double-buffered pixel surface for graphics.
- writable Incudela FS **(done)**: `tools/incudela-part.py create DISK MIB --yes-add-incudela-partition` is the only way an Incudela partition is made: it validates the GPT, adds one entry with the Forge type GUID D0C2E3A1-6B7F-4F0A-9E11-466F72676546 in the largest free gap, rewrites only the primary/backup headers and entry arrays, and zeroes the new partition's first 4 KiB. The kernel (`ffs.cudi`) checks the GPT header and entry CRCs, requires exactly one Incudela partition, inside the usable range, 4 KiB aligned and overlapping no other entry, then calls `nvme_claim(lo, hi)`; `nvme_write` refuses (and counts) any LBA outside that range, and without a claim the NVMe driver writes nothing. It formats only a blank (all-zero) superblock and refuses to format anything else. Layout: superblock (magic, version, size, generation, partition LBA, inode-table and superblock checksums), one 64-entry inode table, contiguous first-fit extents; commit order data -> flush -> inode table -> flush -> superblock -> flush. Data moves only through the registered DMA buffer and checked arrays; one new `@unsafe` helper reads string-literal bytes. Test `tests/os/forgefs.sh` (7 checks): a copy of the shared GPT disk (ESP + Windows + Linux partitions filled with data) as NVMe; boot without an Incudela partition -> no writes, disk byte-identical; the tool refuses without its flag and keeps every partition identical; boot 1 formats and writes, boot 2 finds the files with matching hashes; after both boots everything outside the Incudela partition (ESP, other partitions, GPT, gaps) is byte-identical; the host tool reads hello.txt back. The kernel also checks three out-of-range writes (LBA 0, just below and just above the partition) are refused. Gaps: NVMe only, 512-byte sectors only; flat namespace of 64 files, contiguous extents (no fragmentation handling), no journal (a torn inode-table write is detected by the checksum but not repaired); not exposed through the VFS/syscalls to user programs yet; the kernel never edits the GPT itself.

**Drivers:**

| Driver | Test |
|---|---|
| NVMe | Read-only in QEMU `-device nvme` |
| AHCI | QEMU `-device ahci` |
| xHCI with a USB keyboard and mass storage | QEMU `qemu-xhci` |
| virtio-net, then e1000 | ARP/ICMP, then a UDP echo through QEMU user networking (done: both NICs) |
| GOP mode setting and a double-buffered console | — |

Each driver gets its own boot test, and none of them writes to disks it does not own.

**Writable storage:** an ext2- or log-structured Incudela FS, only on a Forge-owned GPT partition that is created explicitly. Test: crash-consistency fuzzing in QEMU (kill the VM at random points, then fsck).

## Phase 9 — Living object store replacing files (signature feature 3)
- Typed objects (schema in Forge types), with every write versioned (copy-on-write, content-addressed), plus indexed search by type, field, and full text.
- `rewind` works for any object or the whole system to a timestamp.
- The POSIX-like VFS becomes a view onto the store.
- Tests: write/rewind/diff round-trips; system rewind after a bad change in QEMU; search latency on 100k objects; crash consistency.
- Sub-items: 9.1 store core (typed objects, CoW versions, content-addressed blobs, read-at, rewind, diff); 9.2 persistence on the Incudela partition with crash consistency; 9.3 indexed search (type, field, full text) with the 100k-object latency test; 9.4 system rewind after a bad change in QEMU; 9.5 the VFS as a view onto the store.
  - **9.1 status: done.** `examples/kernel/obj.cudi` (fully safe Forge, shared by the kernel and hosted tests): a type table gives each type its field count and writes of the wrong shape are refused; every write appends an immutable version (object, blob, previous version, logical timestamp) and never touches older ones; payloads are content-addressed blobs (FNV-1a + word compare, identical payloads share a blob); `obj_read_at`, `obj_rewind` (a rewind is itself a new version, so history is kept), `sys_rewind` (every object back to a timestamp), `obj_diff` (fields changed between two times) and a linear `obj_find` (the index is 9.3). Test: tests/fs/objstore.cud covers write/read-at/rewind/diff round-trips, dedup, shape checks and a whole-system rewind after 200 bad writes, at O2 and O0.
  - **9.2 status: done.** Every mutation in obj.cudi appends one self-checking record to a write-ahead log (type, object, blob with its words, version; each ends with an FNV of the record). Records only refer to earlier ones, so any prefix is a consistent store; `ob_replay` rebuilds the store and stops at (and truncates) the first torn, corrupt or out-of-order record. Test: tests/fs/objlog.cud cuts the log at every word (638 cuts) and flips a bit in every word: every result is a consistent prefix of history (fingerprint equals the reference store at that timestamp), every corruption is detected, and writes after recovery survive the next replay. On disk (`examples/kernel/objd.cudi`): the log is the Incudela FS file `objects.log` (64 blocks, reserved zero-filled, so it exists only on the explicitly created Incudela partition and every write goes through ffs/nvme_write, which refuse anything outside it); each commit writes the log blocks it dirtied and flushes before returning. Mount replays it, then zeroes any torn/corrupt tail in memory and on disk so a later append can never revive stale records. QEMU test os/objstore-crash-recover (tests/os/forgefs.sh): boot 1 creates the log, makes its durable commits (type, objects, 60 writes, each flushed) and then writes a torn version record; boot 2 recovers, drops the torn tail, reproduces boot 1's fingerprint exactly, reads back all 50 versions of object 0 at their timestamps, rewinds and commits again.
  - **9.3 status: done.** Indexes in obj.cudi (derived state kept current by every write, rewind and replay): a blob hash table (O(1) dedup), per-type object lists, and one hash index over (type, field, value) plus full-text terms of fields declared with `ob_type_text` (new log record OB_RX). Lookups recheck candidates against the current version, so stale entries never leak; if the index fills, lookups fall back to the scan. Capacities are now consts set by the includer. Test: tests/fs/objindex.cud, 100k objects: every lookup agrees with the linear scan, stays right after an update, a rewind and a replay, and indexed lookups are >= 50x (field; ~50 vs ~1.5M cycles) and >= 20x (full text) faster than scanning.
  - **9.4 status: done.** System rewind after a bad change, in QEMU (objd.cudi `objrw_test`/`objrw_verify`, tests/os/forgefs.sh boots 2 and 3): a typed system configuration lives in the store; a bad change to every slot is committed durably, the health check detects it, `sys_rewind` takes the whole store back to the last good clock (the bad versions stay in history) and the result is committed. The state fingerprint equals the pre-change one, and the next boot replays the log and finds the rewound, healthy state with the same fingerprint. Tests: os/objstore-system-rewind, os/objstore-rewind-persists.
  - **9.5 status: done.** Files as objects (examples/kernel/objfs.cudi): a file is an object (name hash indexed, name, size, up to 464 bytes of contents) and every write is a version; `/obj`, `/obj/<name>`, `/obj/@<clock>/<name>` and `/obj/@<clock>` are served read-only through open/stat/read/getdents (proc.cudi), with handles snapshotting their clock. Tests: tests/fs/objfs.cud, os/objfs-vfs-view, os/objfs-persists. Limits: files are at most 464 bytes and read-only through the VFS (writes go through the objfs API in the kernel); the QEMU test drives the kernel path resolver, not a userland open of /obj.

## Phase 10 — Private by design (signature feature 4)
- Per-user keys (TPM-sealed when available), with every object and swap page encrypted at rest.
- Per-app access grants are visible in one ledger and revocable live, and revocation takes effect on open handles.
- Tests: the disk image contains no plaintext; revoking access cuts an app off mid-read; an audit log of every grant and use is kept.
- Sub-items: 10.1 per-user keys and objects encrypted at rest; 10.2 the per-app grant ledger with live revocation on open handles; 10.3 the audit log of every grant and use.
  - **10.1 status: done.** `examples/kernel/crypt.cudi` (ChaCha20, SHA-256, HMAC-SHA256, constant-time compare; RFC 8439 / FIPS 180 / RFC 4231 KATs in tests/fs/crypt.cud) and objd.cudi: a random data key per store, stored only wrapped by the user key (the platform key from QEMU fw_cfg `opt/forge/userkey`; a TPM hook exists but TPM sealing is not implemented) in `objects.key`; every `objects.log` block is encrypt-then-MAC: ChaCha20 under K_enc (nonce = write counter + block; counters never reused, backed by a durable high-water mark in `objects.ctr`) then a full HMAC-SHA256 tag under a separate K_mac, and alternates between two slots so a torn write keeps the old slot. Without a key or with a wrong key the store stays locked and untouched. Tests: os/objstore-key-wrap, os/objstore-no-plaintext, os/objstore-nonce-unique, os/objstore-tamper-rejected, os/objstore-wrong-key-locked; all Phase 9 QEMU tests run encrypted. Limits: no TPM in the test setup (sealing not implemented), Cuditor has no swap, one user per store, Incudela FS metadata is plaintext, no rollback protection without a TPM counter. See docs/privacy.md (threat model).
  - **10.2 status: done.** `examples/kernel/grant.cudi`: every handle sh installs from an app manifest becomes a grant in a 64-entry ledger (app, path, rights, pid, state, uses, denials). The grant id lives in the File object, so dups, forked copies, channel-passed handles and files opened through a granted directory are revoked together. read/write/getdents/openat/dup check it on every call (zero-length reads too) and return EACCES once revoked. Syscalls 428 grant_revoke / 429 grant_list need the new `grant` capability (128), which only sh declares; sh builtins `grants`, `revoke app`, and `run app &`. Test (tests/os/run.sh): grtest reads half of big.bin, then `revoke grtest` cuts it off mid-read: read, read on an earlier dup, and dup all get EACCES; the ledger shows revoked/ended entries. Limits: data already read is not taken back; revoke is per app; the ledger is not carried across kexec. See docs/privacy.md.
  - **10.3 status: done.** `examples/kernel/audit.cudi`: every grant event -- granted, each use (read/write/getdents/openat/dup/poll, with bytes moved), each denial, revocation (with the revoking pid) and end -- is appended in order to a 256-record kernel ring. Consecutive identical uses coalesce into one record with a count, so every use is counted without flooding; eviction is counted, never silent. Syscall 430 audit_dump (capability `grant`, sh builtin `audit`) prints the log and cross-checks it against the ledger (uses and denials per grant must match). Test (tests/os/run.sh): after the grtest revocation, `audit` shows 16 records (grtest: dup x1, read x12 / 49152 bytes, polls, revoked by sh, poll/read/dup denied) and `ledger check: ... match ... for all 3 grants`. Limits: in memory only (not persisted, not carried across kexec, not signed). See docs/privacy.md.

## Phase 11 — Linux compatibility and FFI
*Pillar: F.*
1. Linux syscall ABI personality for static ELF binaries:
   - read, write, openat, close, fstat, mmap, brk, exit_group, clone (threads), futex, getdents64, ioctl (tty subset);
   - auxv and argv.

   Test: static musl `busybox` runs `ls`, `cat`, and `sh` in a sandbox.
   - **11.1a status: done (personality core; busybox not run yet).** `examples/kernel/linux.cudi`: a sealed image tagged EI_OSABI = 3 launched with sh `run app` (sys_exec with sb = 1, verified as `SEAL_USER | SEAL_COMPAT`) gets `Proc.abi = LX_ABI` and reaches only the Linux table: read, write, close, mmap (anonymous private; PROT_EXEC -> EACCES, MAP_FIXED -> EINVAL), munmap, brk, ioctl (TCGETS, TIOCGWINSZ; ENOTTY/EBADF), getpid, getppid, gettid, set_tid_address, exit, exit_group; anything else (all Incudela syscalls included) is -ENOSYS and logged. exec builds the System V start stack (argc, argv, empty envp, 9 auxv entries incl. AT_RANDOM). The syscall frame now saves rdi/rsi/rdx/r10/r8/r9 (128 bytes) and restores them, as the Linux ABI requires (kexec handoff format v4). The 6.4 gate is unchanged for every other path: plain exec, boot and the self-test still refuse Linux images (reason 6), unsealed ones are refused first. Test (tests/os/run.sh): `lxtest` (examples/user/lxtest.cud, raw syscalls only, built with cudc/fas/fld) is refused from plain sh and passes 19 checks under `run lxtest`. Next: 11.1b clone threads, futex, arch_prctl TLS; 11.1c openat, fstat, getdents64. Busybox waits for approval to download it. See docs/linux-compat.md.
   - **11.1b part 1 status: done (TLS).** Per-thread user FS base: `Thread.fsbase`, reloaded into IA32_FS_BASE by `schedule_l` when it differs (the kernel never uses FS); Linux `arch_prctl` (ARCH_SET_FS below USER_TOP, ARCH_GET_FS) and `sched_yield`; fork copies, exec clears, kexec carries it (record +120). Test: lxtest reads its `%fs:0` self pointer 400000 times across yields and preemptions with 0 bad reads, 25 checks. Next: part 2, clone threads + futex.
   - **11.1b part 2 status: done (threads).** Linux `clone` of threads (sys_fork in thread mode: same Proc and page tables, new kernel Thread on the given stack, SETTLS / PARENT_SETTID / CHILD_SETTID / CHILD_CLEARTID), `futex` WAIT/WAKE over a 64-entry wait table, per-thread `gettid` / `set_tid_address`, thread `exit` vs `exit_group`, group exit that reaches threads spinning in user mode (timer tick) or asleep in a futex. All threads of a process are pinned to one CPU (documented limit). New helpers `as_thread` / `as_proc` replace two @unsafe cast functions (count unchanged at 156). Test: `run lxthreads` (4 workers x 2000 futex-locked increments = 8000, TLS per thread, join via CLEARTID, group exit; 10 checks).
   - **11.1c status: done (files).** Linux `openat` (only relative to a granted directory handle; AT_FDCWD / absolute / `..` -> EACCES, write flags -> EROFS, O_DIRECTORY checked), `fstat` (synthesized struct stat for files, dirs, /obj, console, pipes) and `getdents64` (Forge records converted to linux_dirent64; buffer >= 768 bytes). `dir_read` / `odir_read` gained a kernel-buffer mode for the converter (no new @unsafe; count 156). Linux personality now 20 syscalls. Test: `run lxfs` (14 checks). 
   - **11.1d part 1 status: done (execve).** Linux `execve` / `execveat` (AT_EMPTY_PATH): only sealed Linux images, reached through a handle the sandboxed process holds (absolute path under a `dir` grant's label, or relative to a dirfd); the process keeps its sandbox, pid and handles minus O_CLOEXEC, caps narrowed by the new seal. `sys_exec`'s image switch factored into `exec_image` (shared); `fs_read_clu` reads a file by its handle. 22 Linux syscalls. Test: `run lxexec` (3 images, 21 checks). Next: signals (11.1d part 2), then busybox once a download is approved.
   - **11.1d part 2 status: done (signals).** rt_sigaction / rt_sigprocmask / rt_sigreturn, kill and tgkill limited to the process itself (other pids -> EPERM), delivery at syscall exit with a Forge-layout frame, SIGSEGV to a handler on a user page fault, default actions (exit 128+sig or ignore). 27 Linux syscalls. Test: `run lxsig` (34 checks) and `run lxsig term` (exit 143). Next: busybox once a download is approved. rt_sigreturn leaves by iretq and so restores rcx and r11 too (thread `sig_rx`, flagged through the syscall frame's pad word); lxsig checks both survive a resumed SIGSEGV (35 checks).
   - **11.1e status: acceptance started (BusyBox 1.38.0 runs).** `tools/busybox/build.sh` builds BusyBox 1.38.0 statically against musl 1.2.5 from source tarballs pinned by SHA-256 (BusyBox signature checked: GOOD, Denys Vlasenko C9E9416F76E610DBD09D040F47B70C55ACC9965B; musl key unavailable, SHA-256 pin + Alpine sha512 match), host gcc 14.2.0, GNU make 4.4.1 from verified source. Tagged EI_OSABI 3 and sealed with the new foreign level (`cudseal.py --foreign`: level 3, caps 0; the kernel refuses level 3 unless OSABI 3 with no caps, seal reason 8). Runs only via `run busybox` in the compat sandbox. Working: echo, true, false, basename, env. Missing syscalls seen: writev(20), uname(63), open(2), stat(4), getcwd(79), nanosleep(35), fcntl(72); added one per commit next. See docs/linux-compat.md.
   - **11.1e part 2 status: done (writev).** Linux `writev` (20): iovecs copied in one by one, each through sys_write (same fd checks), IOV_MAX 1024 -> EINVAL, bad iov -> EFAULT, partial count on a later fault or short write. 28 Linux syscalls. Tests: lxtest (28 checks: 3-iovec line, EINVAL/EFAULT, EBADF, iovcnt 0); `run busybox seq -s , 3 5` -> 3,4,5 and `expr 6 + 7` -> 13.
   - **11.1e part 3 status: done (uname).** Linux `uname` (63): struct utsname packed from constants (sysname Linux, nodename forge, release 0.2.6-forge, version `#1 Forge Linux compat sandbox`, machine x86_64, domainname (none)); bad pointer -> EFAULT. 29 Linux syscalls. Tests: lxtest (30 checks), `run busybox uname -s -m` -> `Linux x86_64`.
   - **11.1e part 4 status: done (open).** Linux `open` (2) and `openat(AT_FDCWD, absolute)`: still no cwd; an absolute path naming a held dir handle's label (dup) or under it (openat of the rest) opens, everything else EACCES. 30 Linux syscalls. Tests: lxfs (18 checks), `run busybox wc -c` / `sha256sum` of big.bin (hash checked against the host), `cat /efi/incudela/bin/cat` -> Permission denied.
   - **11.1e part 5 status: done (stat).** Linux `stat` (4): open's path rules, fstat, close. 31 Linux syscalls. Tests: lxfs (22 checks: file, granted dir, outside -> EACCES, missing -> ENOENT, bad buffer -> EFAULT), `run busybox ls /efi/incudela/bin` -> Permission denied. `ls` of the granted dir next needs lstat (6) and fcntl (72).
   - **11.1e part 6 status: done (lstat).** Linux `lstat` (6) = stat (no symlinks on FAT32). 32 Linux syscalls. Tests: lxfs (23 checks: lstat file, outside -> EACCES).
   - **11.1e part 7 status: done (fcntl).** Linux `fcntl` (72): F_DUPFD / F_DUPFD_CLOEXEC, F_GETFD / F_SETFD, F_GETFL, no-op F_SETFL. 33 Linux syscalls. Tests: lxfs (28 checks), `busybox ls /efi/incudela/docs` lists both files, `busybox printf %d-%s 42 ok` -> 42-ok.
   - **11.1e part 8 status: done (getcwd).** Linux `getcwd` (79) always returns "/" (no working directory; relative paths stay EACCES). 34 Linux syscalls. Tests: lxtest (getcwd, ERANGE, EFAULT), `busybox pwd` -> /.
   - **11.1e part 9 status: done (nanosleep).** Linux `nanosleep` (35): 10 ms ticks, rounded up, capped at a day, not signal-interruptible yet. 35 Linux syscalls. Tests: lxtest (30 ms sleep, EINVAL, EFAULT), `busybox sleep 1`.
   - **11.1e part 10 status: done (geteuid).** Linux `geteuid` (107) returns 1000, matching AT_EUID in the auxv (no root in the sandbox). 36 Linux syscalls. Tests: lxtest (geteuid == 1000), `busybox sh -c exit 3` -> exit 3 with no ENOSYS.
   - **11.1e part 11 status: done (dup2).** Linux `dup2` (33): dup's rules, then the copy moves to newfd (old newfd closed after the dup succeeds), FD_CLOEXEC cleared. 37 Linux syscalls. Tests: lxfs (dup2 free / over an open fd / same fd / EBADF), `busybox sh -c 'exit 4 </efi/incudela/docs/big.bin'` -> exit 4 (the redirection goes through dup2).
   - **11.1e part 12 status: done (lseek).** Linux `lseek` (8) on FAT32 files (SET/CUR/END, past the end ok, below 0 EINVAL), directories rewind only, console ESPIPE. 38 Linux syscalls. Tests: lxfs (lseek checks), `busybox tail -n 2 /efi/incudela/docs/hello.sh` (a small text file now on the ESP) with no ENOSYS.
   - **11.1e part 13 status: done (ppoll).** Linux `ppoll` (271), non-blocking: held objects ready, closed fds POLLNVAL. 39 Linux syscalls. Tests: lxfs (ppoll checks).
   - **11.1 status: accepted (BusyBox ash runs a script).** `busybox sh /efi/incudela/docs/hello.sh` (examples/efi/scripts/hello.sh, on the ESP under \EFI\Incudela\docs) runs in the compat sandbox: a shell function, `for` / `while` loops, `$((...))` arithmetic, `case`, `if test -f`, a `while read` loop over the LFN notes file through a `<` redirection, and `printf` -- 9 lines of output, exit 0, no ENOSYS. busybox.config now enables the ash echo / printf / test builtins, shell arithmetic (64-bit), test, grep and the fancy head/tail options (still sealed and built from the pinned sources). Also working as applets: head, tail, grep, sort, cut, md5sum, sha256sum, wc, ls (-l), cat, pwd, sleep, printf, seq, expr, uname. Not in 11.1 (needs fork + pipe): ash running external commands, pipelines and command substitution with a subprocess; those fail cleanly ("Permission denied" / ENOSYS for clone(fork), pipe 22), no kernel change of behaviour. Visual: /workspace/forge-shots/ (ash-accept).
2. C FFI with the SysV ABI (`extern "C"`, struct layout). Test: link against a C object file and call both ways.
   - Status (in progress, one item per commit): stack arguments done — calls with more than 6 integer words pass words 7+ on the stack (rsp 16-aligned, odd counts padded) in both directions and between Forge functions (tests/fs/cabi8). Structs by value and struct returns done: SysV classification (INTEGER structs up to 16 bytes in one or two registers / rax:rdx, MEMORY structs over 16 bytes on the stack and returned through a hidden pointer in rdi), both directions (tests/fs/cabi_struct). Floats done: `f64`/`f32` types (literals, + - * /, comparisons with NaN = unordered, unary minus, explicit `f64()`/`f32()`/`i64()` casts, integer literals convert implicitly, nothing else does), passed in xmm0-7 (9th+ on the stack, `%al` = xmm count for varargs) and returned in xmm0, mixed with integer registers, both directions (tests/fs/cabi_float). Structs with float fields done: each eightbyte of a struct up to 16 bytes is classified SSE (only float fields, including nested structs and arrays) or INTEGER (anything else in it), SSE eightbytes go in the next xmm register and INTEGER ones in the next GPR (mixed structs split across xmm + gpr; if either class runs out the whole struct goes on the stack and later arguments still use the free registers), returns in xmm0/xmm1 and rax/rdx in eightbyte order, over 16 bytes still MEMORY; both directions (tests/fs/cabi_floatstruct). 11.2 is complete.
   - **Plan v1.3 queue (approved order, one commit each, inserted before structs with float fields):**
     1. Provenance rule — **done.** Integer-to-pointer conversions (implicit or `ptr[T](n)`) only inside `@unsafe` functions, enforced by `cudc --provenance-lint` (lists every site; any in a `with unsafe:` block or elsewhere fails) over every baseline program in tests/unsafe/run.sh; pointers passed to C keep their provenance (passing a pointer to an integer extern parameter is a compile error; tests/unsafe/bad_cptr). Kernel: 116 sites, 0 outside @unsafe; unsafe baseline unchanged.
     2. [done] Seal v3: version field, algorithm ID, room for several signatures, a reserved proof slot; Ed25519 only; v2 seals still readable.
     3. [done] (11.2) Structs with float fields by value (SysV eightbyte classification; tests/fs/cabi_floatstruct).
     4. [done] Reserve effect syntax in GRAMMAR.md and the AST (names = the Phase 6 capability names); the checker rejects it for now. Syntax `def f(...) [-> T] uses fs, ipc:` (grammar v1.2, soft keyword); AST: optional `Effects` child of `Def`; pretty-printer round-trips it; the checker rejects it with E0106 (hosted and freestanding). Tests: tests/grammar/{valid/effects, invalid/effect_unknown, invalid/effect_trailing_comma}, tests/diag/effects_reserved{,_method,_freestanding}.
     5. [done] docs/rfc: query-based incremental compiler (no refactor). docs/rfc/incremental.md: module/function granularity, the query table, dependency graph with early cutoff and a per-function-summary worklist for the inference fixpoint, content-addressed cache keyed by compiler identity + flags, LSP integration, byte-identical output so FIXPOINT/SEED/seals are unaffected, test strategy and a 4-step rollout. Design only; no compiler code changed.
     6. [done] One nondeterminism hook point (syscall results, timers/interrupts, scheduler choices, RNG), recording off by default. examples/kernel/nondet.cudi: `nd_hook(kind, a, v)` returns v (the place a later replay mode substitutes values); called from syscall_dispatch (now a thin wrapper around syscall_do, so every native and Linux-personality syscall result passes it), on_lapic_timer, schedule_l (the picked thread) and `nd_rand` at every random site (KASLR slide, stack canary, Linux AT_RANDOM, object-store key entropy). Recording (`nd_rec`) is off by default; when on, per-kind counts and a 256-entry ring (atomic slot index). Boot self-test: nothing recorded before the shell session, then a recorded window over it must contain all four kinds and nothing after it is switched off (tests/os/run.sh: `nondet: recording off by default`, `nondet hook OK`). Unsafe counts unchanged.
     7. [done] kexec handoff record = the single versioned process-state format. examples/kernel/pstate.cudi defines process-state v1: the two-page per-process record (named offsets PS_PID .. PS_FRAME, FPU page) plus a header word at +512 (`PS_MAGIC << 32 | PS_VERSION`, `PS_MIN_VERSION`, `ps_hdr_ok`). kexec writes and adopts exactly these records (handoff format v5; a record whose header fails is refused); any later user of process state (checkpoint, migration, replay) must use it and bump PS_VERSION. Boot check `ps_selftest` (own header accepted; wrong magic, version 0 and a newer version refused). Kernel unsafe ops fell from 715 to 710 (the record's scalar words are stored in one loop); baseline unchanged.
     8. [done] Interface spec for the kernel core (scheduler, IPC, capabilities). docs/kernel-core.md (spec v1): conventions (error values, `rq_lock` and the `_l` rule), the scheduler (thread states and legal transitions, spawn/yield/exit/sleep, wait queues, mutex, condvar), the two capability layers (per-process syscall classes from the sealed manifest, per-handle rights that only shrink, fd 3 as the only ambient authority, grants), IPC channels (message size, ordering, handle move, blocking, close and EPIPE/EMFILE/EFAULT rules), five system guarantees and what is not yet specified. Describes the current code; no kernel change. Appendix A (verification scope, plan v1.8 item 5; docs only): what is verified and by which tests/markers, what is not, the assumptions, the DMA/IOMMU gaps as first written (pass-through default rather than default-deny, no interrupt remapping, only the first DRHD programmed, no DMAR fault logging, no requester-ID aliasing behind PCIe-to-PCI bridges, no context-table sizing or coverage checks, no policy for a machine with no remapping unit; all seven are closed since, see Appendix A.2 and the IOMMU hardening entries under Phase 2), and a one-page set of verifier-ready conventions.
     9. All-Forge tooling (Kyle's standing direction: anything that can be written in Cuditor should be). Port the Python tools to Forge, one tool per commit, each checked byte-for-byte against the Python output before the .py is removed: tools/cudseal.py (the sealer; seal v3 is where it starts), tools/ed25519.py, tools/incudela-part.py, tools/krel.py, tools/mkfont.py, tools/grammar_fuzz.py, examples/efi/mkgpt.py. Replace selfhost/runtime.s with Forge inline asm where possible, and move the build/test shell scripts to Forge where practical. Stays C: BusyBox (the Linux test program) and the C FFI test files. One item per commit with the full checks. *Status: done.* Every listed tool is ported and checked byte-for-byte (tools/cudseal.cud, tools/ed25519.cud, tools/incudela-part.cud, tools/krel.cud, tools/mkfont.cud, tools/grammar_fuzz.cud, examples/efi/mkgpt.cud); runtime.s is now selfhost/runtime.cud (naked functions + inline asm); the test helpers (pecheck, memimg, lsp client, boot, ed25519 gen) and cud_test.sh, cud_verify.sh, reseed.sh, fmt_files.sh have Forge versions. The .py/.sh originals stay as byte-for-byte references until Kyle decides on removal. Build scripts: examples/modules, examples/user, tools/busybox, examples/efi and examples/kernel build.sh are ported (entries below); remaining: build.sh/run_tests.sh (needs a decision). Details: section "All-Forge tooling" below.
3. Cuditor language server: extend the existing `cuditor lsp` (tools/lsp.cud, Phase 7.5, tests/lsp/run.sh) rather than write a new one (approved). Additions: incremental re-check of changed files (and incremental text sync) instead of recompiling the whole file on every change, plus closing the gaps listed under 7.5 (attribute resolution on objects, references, completion, UTF-16 positions). New checks go in tests/lsp/run.sh. Placed right after 11.2 C FFI. **Done** (see the 7.5 status: incremental sync, UTF-16, re-check caching and dependents, attributes, references, rename, completion; 45 checks).
4. C-to-Forge translator (approved). Written in Forge, for a C subset: functions, structs, pointers, integer and float types, control flow. Output is `@unsafe` Forge, made safe over time. Placed after 11.2 (it needs the C ABI types, floats included) and after the v1.3 queue. First test: translate one small real C library (a compression or crypto routine) and compare the translated program's output against the C build. *Status: planned subset (steps 1–7) done; remaining gaps listed (0.15.1); silent mistranslations are now clean errors* (tools/c2cud.cud, tests/c2cud/run.sh). The output targets freestanding (`# cuditor: no-runtime`) Forge, whose `ptr[T]`, fixed-width ints, `f64`/`f32` and structs match the 11.2 C ABI. Steps, one commit each:
       1. [done] C lexer: identifiers and keywords, integer literals (decimal, hex and octal, with u/l suffixes), float literals, char and string literals (escapes kept), every C operator using longest match, and both comment styles. A preprocessor line, including its continuations, becomes one `pp` token and is not expanded. `c2cud --tokens IN.c` dumps the stream. Test: lex.c against lex.expected, plus a clean error with exit 1 on a bad character.
       2. [done] Parser and emitter for functions over integer types: declarations, expressions with C precedence, if/while/return. The integer types map to i8..u64. Test: the Forge output and a gcc build must print the same thing: tests/c2cud/ints.c (with shim.c for the gcc build) matches at -O2 and -O0, and `x++` inside an expression is a clean error.
       3. [done] Full control flow: for, do/while, break/continue, switch, and the ternary. Test: tests/c2cud/flow.c (switch fall-through, default in any position, nested loops with break/continue) matches the gcc build at -O2 and -O0.
       4. Pointers, arrays and structs mapped to `ptr[T]`, fixed arrays and Forge structs, with `->`, address-of and pointer arithmetic, all emitted inside `@unsafe`. [done: tests/c2cud/ptrs.c matches gcc at O2/O0; C `T a[N][M]` becomes `T[M][N]`, null is `ptr[T](u64(0))`, struct copies go through memcpy, brace initializers zero then store; void *, casts and unions wait for step 5]
       5. Floats (`double`/`float` to `f64`/`f32`) and casts. [done: tests/c2cud/floats.c matches gcc at O2/O0 (values and raw double bits); C's usual arithmetic conversions, every conversion explicit as `T(x)`, float conditions compare with `T(0)`; casts number<->number, pointer<->pointer `ptr[U](p)`, int->pointer `ptr[T](u64(x))`, pointer->int `T(u64(p))`, `(void)x`; `void *` converts implicitly to/from object pointers and is emitted as `ptr[u8]` (deref/index/arithmetic on it are errors); `long double`, hex floats, `%`/shifts/bit ops on floats, float<->pointer casts and unions are clean errors (Cuditor has no unions and the plan does not add them); out-of-range float->int casts are C UB and not tested]
       6. Preprocessor subset: object-like `#define` constants, with `#include` of standard headers mapped to types. [done: a token-level `preprocess` pass before parsing; tests/c2cud/pp.c matches gcc at O2/O0. Object-like `#define`/`#undef` (nested, line-continued, redefined), recursive expansion where a macro is not re-expanded inside itself (`#define SELF SELF`); expanded tokens carry the line of the use. `#include <stdint.h>`/`<stddef.h>`/`<sys/types.h>`/`<limits.h>` make that header's typedef names types (a typedef name without its header is not a type, as in C) and define its limit macros (INT_MAX, UINT32_MAX, SIZE_MAX, NULL, ...). Function-like macros, `#if`/`#ifdef` and other directives, quoted and unknown headers are clean errors. Array sizes must still be integer literals (constant expressions are not folded)]
       7. First real library: translate one small C compression or crypto routine and compare the translated program's output with the C build. [done: tests/c2cud/lib.c, written in reference style and translated with no workarounds: zlib-style table-driven CRC-32 (polynomial 0xedb88320, incremental update), zlib's Adler-32 with NMAX-deferred modulo, and the XTEA reference encipher/decipher (32 rounds). Output matches gcc at O2/O0: the standard check values for "123456789" (crc32 0xcbf43926, adler32 0x091e01de), CRC split across two calls equal to one call, a 20000-byte Adler run past NMAX, and XTEA round-trips of 4 blocks]
   Remaining gaps, checked against the translator (0.15.1). File-scope variables are now translated (0.15.2): integer, float, array and struct globals become Forge globals; an integer scalar may have an integer constant expression initializer (literals, character constants, `sizeof(type)`, parentheses, unary `+ - ~`, `* / %` truncating as in C, `+ -`, `<< >>`, `& ^ |`; tests/c2cud/cinit.c, 17 globals, matches gcc at O2/O0; an unsigned operand together with a negative value, division by zero and a shift count outside 0–63 are clean errors), wrapped to its type as C converts it. A 1-D integer array global may have a brace list of such expressions (`int primes[6] = {2, 3, 5, 7, 11, 13};`, zero padded, trailing comma allowed), and `T a[] = {...}` takes its size from the list, at file scope and for locals (including `int g[][3] = {{...}, {...}, {7}}` and local float arrays); tests/c2cud/braces.c matches gcc at O2/O0. Float and double globals take initializers too: a float literal or an integer constant expression, with any signs (`double rate = 0.075;`, `float folded = -(1 << 4);`, `double t[6] = {1.5, -0.25, 1e10, 2, .5};`, `float c[] = {0.1, 1e-40f, 16777217};`), emitted as Forge float globals whose IEEE bits cudc computes (f32 rounded to nearest even from the double value; tests/c2cud/fglobals.c matches gcc at O2/O0, including -0.0, f32 overflow-to-max, a subnormal and a tie). A non-constant float element is `a float global initializer must be a constant`. Multi-dimensional arrays with a file-scope brace list are clean errors, as is a list longer than the array. Tentative definitions and `extern` redeclarations merge: `int counter; ... int counter;`, `extern int limit; ... int limit = 7;` and `int table[4]; ... int table[4] = {10, 20, 30};` give one Forge global with the one initializer (tests/c2cud/tentative.c matches gcc at O2/O0); a second initializer is `redefinition of`, another type is `conflicting types for` (`unsigned char w = 300;` is 44, `short n = -40000;` is 25536); everything else is zero-initialized. tests/c2cud/ints.c uses them (a counter changed from a helper, a histogram array, a float accumulator) and matches gcc at O2/O0. Still clean errors (tested): pointer globals (`pointer global variables are not supported yet`; a Forge `ptr[T]` global needs a non-null initializer), a non-constant initializer (`global initializer must be an integer constant`), a float initializer for an integer global (`needs a cast`), and a local or parameter with a global's name (`local g shadows a global variable (not supported yet)`). String literals are values (`const char *s = "hi"`, adjacent concatenation, `sizeof("hi")`); `char s[] = "hi"` and `char s[N] = "hi"` copy the bytes (a NUL is stored when it fits; `char s[1] = "hi"` is `too many initializers`); tests/c2cud/strlit.c matches gcc at O2/O0. File-scope `const char *s = "hi"` is still rejected with the file-scope pointer error. `++`/`--` now works in expressions (prefix and postfix, including on pointers and `*p`; tests/c2cud/incdec.c matches gcc at O2/O0; `++(x + 1)` is `++/-- needs an lvalue`). Array sizes may be an integer constant expression (`int a[2+2]`, `int a[sizeof(int)]`, `int a[(1+2)*3]`, `+`/`-`/`*`/`/`/`%`, parentheses, `sizeof(type)`; `/` truncates toward zero and `%` takes the dividend's sign as in C, so `int a[7/2]` has 3 elements, not `3.5`; tests/c2cud/arrconst.c matches gcc at O2/O0). A non-constant size (`int a[n]`) is still `array size must be an integer constant`. lib.c still builds the "123456789" buffer from bytes.
   Other rejected C (clean errors; several already tested): unions, hex floats, long double, function-like macros, `#if`/`#ifdef`, unknown headers, the comma operator, compound literals, `continue` inside a switch, `enum`, `goto`, varargs (`...`), a local `typedef`, bit-fields, K&R definitions, `__attribute__`, GNU statement-expressions, `_Bool`, `_Complex`.
   The two silent mistranslations are now clean errors (tests in tests/c2cud/run.sh): `static` local variables (`static int x = 0;` is `static local variables are not supported yet`); an inner-block declaration of the same name and type as an outer variable (`int x = 1; { int x = 2; }` is `inner-block declaration of x shadows an outer variable (block scoping is not supported yet)`). A type mismatch was already a clean error. There are no remaining silent limitations in the planned subset. Supporting these constructs, rather than rejecting them, is future work.
5. Python FFI: embed CPython in hosted mode, with tests calling Forge to Python and back. Target 0.17.0. Decision (2026-11-10): do both (a) a pinned CPython-from-source embed now, and (b) a long-term native Python-in-Forge track (planned only until (a) is done). No distro python3-dev / libpython: CPython is built from official source, pinned by SHA-256 (and upstream GPG when the key is present), like BusyBox. The box already has /usr/bin/python3 3.13.5 and gcc; the embed uses the source build, not that interpreter's missing headers. *Status: 11.5(a) done; (b) Python-in-Forge is still a planned track.*
   1. [done] CPython source build tool plus a pin. `tools/cpython/build.cud` (built to `build/cpython-build`) pins `Python-3.13.5.tar.xz` (SHA-256 `93e583f243454e6e9e4588ca2c2662206ad961659863277afcdb96801647d640`; official MD5 `dbaa8833aa736eddbb18a6a6ae0c10fa` matches) in `$CP_SRC` (default `/workspace/cpython`; the tarball is not in the repo). The `.asc` is verified with the shipped release-manager key (`tools/cpython/keys/thomas-wouters.asc`, Thomas Wouters, fingerprint 7169 605F 62C7 5135 6D05 4A26 A821 E680 E5FA 6305). Configure is `--prefix=... --disable-shared --without-ensurepip --disable-test-modules` (no PGO). Installs `prefix/bin/python3` (reports 3.13.5), `prefix/include/python3.13/Python.h` and `prefix/lib/libpython3.13.a`. A stamp records the pin and flags so a current prefix is a no-op. GNU make comes from PATH, `/workspace/bb/work/bin`, or a pinned make-4.4.1 build. Network is never used by the tool. tests/cpython-build/run.sh (in run_tests.sh): missing tarball (rc 2), pin mismatch (rc 3), bad signature (rc 4), install (version 3.13.5, `print(6*7)` is 42, headers and static lib present), and a warm "up to date" re-run. Skip if the tarball is absent.
   2. [done] Embed API and tests, written in Cuditor: `tools/cpython/embed.cudi` calls libpython's exported C API through the 11.2 SysV C ABI (`Py_InitializeFromConfig`, `PyRun_SimpleString`, `PyCMethod_New`, `PyModule_New`, `Py_IncRef` / `Py_DecRef`, `PyTuple_Size` / `PyTuple_GetItem`, `PyLong_FromLong`, …). No C file: macro-only names are avoided by using the function forms CPython also exports, and varargs `PyArg_ParseTuple` is avoided. `PyConfig` / `PyStatus` / `PyMethodDef` are transcribed from the pinned 3.13.5 headers (release layout); the test checks `sizeof(PyConfig)==448` and `offsetof(home)==296`. Isolated init sets `home` to the install prefix. tests/cpython-embed/run.sh (in run_tests.sh) compiles `api.cud` and `main.cud` (`@export main` is the gcc crt entry) with cudc/fas and links with `gcc -no-pie` against `prefix/lib/libpython3.13.a`, `-ldl -lm -lpthread`, and the box libc — not fld (fld stays no-libc and does not accept `.a` archives; fas objects are not PIC). Python `import forge` then calls `add`, `mul`, `neg`, `answer`, and `sum_to` and checks `add(20,22)==42`, `mul(6,7)==42`, `neg(42)==-42`, `answer()==42`, `sum_to(10)==55`. Skip if the tarball and the prefix are both absent. A missing prefix is filled by `cpython-build` when the tarball is present (warm when current).
   3. [done] Forge-to-Python calls, still in `tools/cpython/embed.cudi` (no C file): `forge_py_eval` (`PyRun_String` on `__main__` with `Py_eval_input`), `forge_py_main_attr` (`PyObject_GetAttrString`), and `forge_py_call_i64` (`PyObject_CallNoArgs` / `PyObject_CallOneArg` / `PyObject_Call` with a `PyTuple_New` of i64s — not varargs `PyTuple_Pack`). tests/cpython-embed/run.sh also checks `eval(6*7)==42`, `py_mul(6,7)==42`, `py_neg(42)==-42`, `py_answer()==42`, and `py_twice_add(20,22)==84` where the Python function calls back into `forge.add` (both ways in one session). 11.5(a) is complete.
   4. [done] Generated layouts and a libpython guard. `tools/cpython/pylayout.cud` (built to `build/pylayout`; `pylayout INCLUDE_DIR [OUT.cudi]`) reads the installed pinned headers (`patchlevel.h`, `pyconfig.h`, `cpython/initconfig.h`, `methodobject.h`), strips comments, resolves `#ifdef`/`#ifndef` against what `pyconfig.h` defines (MS_WINDOWS never), computes the SysV x86-64 C layout itself and writes `tools/cpython/pylayout.cudi`: `PyStatus`, `PyWideStringList`, `PyConfig` and `PyMethodDef` with the C field names in order (so `PyStatus._type`, not the old hand-written `typ`), `*_SIZE` and seven `PYCONFIG_OFF_*` constants, and `py_pinned_version()` / `py_pinned_prefix()`. The hand transcription in `embed.cudi` is gone; it includes the generated file. The generator refuses, with no output, headers that are not 3.13.5 (rc 3), free-threaded (`Py_GIL_DISABLED`, rc 4) or debug (`Py_DEBUG`, rc 5). At run time `forge_py_init` first classifies `Py_GetVersion()` (safe before init): a version other than `3.13.5 ` or an "experimental free-threading build" is refused with a clear error naming the linked version, before PyConfig is touched. `forge_py_layout_ok` now also checks `sizeof(PyWideStringList)` and the seven offsets against cudc's `sizeof`/`offsetof`. tests/cpython-embed/run.sh adds `pylayout-generated` (regenerated file byte-identical to the checked-in one; 448 / home 296 / 32 / 32), `pylayout-not-pinned`, `pylayout-free-threaded`, `pylayout-debug` (copies of the pinned headers edited by the test), and `libpython-guard` (the real library is accepted; synthetic 3.13.4, 3.13.50 and free-threaded version strings are refused with their messages).
   5. [done, inv232] The binding layer on the stable ABI (v1 reservation 5 above): run/eval through
   `Py_CompileString` / `PyEval_EvalCode`, one-argument calls through `PyObject_Call`, and the `stable-abi`
   check in tests/cpython-embed; only the PyConfig init of the embedding host is outside the stable ABI.
   Python-in-Forge (planned track, not started): a native Python implementation written in Cuditor, beginning with a tested subset — functions, ints, strings, lists, dicts, and Forge interop — checked against the output of the pinned CPython 3.13.5 build. Not started; 11.5(a) is done, this track remains planned.

## Phase 12 — Parallelism and performance
*Pillar: E. Also the compiler perf list.*

In plain terms: make Forge code and the Forge compiler fast. Kernel code gets real register allocation, loops
get vectorized, `parallel for` spreads work over all cores, and every speed claim is measured and tracked in bench/.
1. Register allocator and IR backend for fs/kernel mode (today only hosted code uses the IR backend).
   - Plan for this item, in safe steps, each byte-identical for code built without the new flag:
     1. `--fs-opt` (opt-in): leaf functions keep scalar locals in free caller-saved registers, plus a push/pop peephole. Done.
     2. Non-leaf functions: callee-saved registers (rbx, r12–r15), saved in the frame. Done.
     3. Turn `--fs-opt` on for the kernel, after auditing every hand-written asm routine that calls or is called
        by Forge code for SysV register discipline; QEMU boot suite at O2 and O0. Done.
     4. A real IR for fs mode (SSA, liveness-based allocation), reusing the hosted IR passes where the
        value model allows.
   - *Status: step 1 done (2026-11-11).* `cudc --fs-opt` works on each finished function's assembly text and is
     conservative: any call, any instruction outside a short whitelist, any inline asm, any `lea` of the frame,
     any use of %rbp other than a plain 8-byte `mov` between a slot and %rax, or a stack protector leaves the
     function unpromoted. The most-used slots get the caller-saved registers (r8–r11, rsi, rdi) that the body never
     names. A peephole then turns `push %rax; mov X,%rax; mov %rax,%rcx; pop %rax` into `mov X,%rcx`, drops
     `push %rax; pop %rax`, and drops a reload right after a store to the same register; it runs in every function
     without inline asm. The kernel assembly gets 14% shorter with the flag (167,471 to 143,557 lines), but the
     kernel and every other build stay byte-identical without it. Tests: every tests/fs program runs again with
     `--fs-opt` and must print the same (`PASS fs-opt ...`); tests/fs/regalloc.cud covers loops, %cl shifts,
     division, narrow wrapping types, more locals than registers, six parameters, an address-taken local and
     unsigned compares, and `fs-opt-shape` checks that ra_leaf has no frame access and ra_addr keeps its slots.
     bench: fsloop 297.5 to 292.2 ms, fsfib 18.9 to 18.1 ms. The loop's `idiv` by 7 dominates (hosted code divides
     by a constant with a multiply), so the next speedup is constant division.
   - *Constant division under `--fs-opt` (2026-11-11).* `x / d`, `x // d` and `x % d` with a literal 0 < d < 2^31
     become multiply-and-shift code instead of `div`/`idiv`. Freestanding division truncates toward zero, so signed
     x is divided as |x| with the 64-bit magic floor(2^(63+k)/d) + 1 and the sign is put back; unsigned x uses the
     65-bit round-up magic (high64(x·m') plus the halving add). Powers of two become shifts (with the
     round-toward-zero bias for signed x) and masks. tests/fs/cdiv.cud compares 90 (type, d) pairs across
     i8–i64 and u8–u64 against division by a variable over 4,615 values (edges and a pseudo-random sweep): 0
     mismatches. `fs-opt-cdiv-shape` checks that only the divisions by a variable keep div/idiv.
     bench: fsloop 296.7 ms without `--fs-opt`, 184.2 ms with it (-38%; Rust -O3 83.3 ms).
   - *Step 2 done (2026-11-11).* Functions with calls now promote too: their slots go to the callee-saved
     registers (rbx, r12–r15) that the body never names, saved in extra frame words right after `sub $n,%rsp`
     and restored before every `leave` (16-byte alignment kept). A callee-saved register only takes a slot used
     at least 3 times (it costs a save and a restore). The caller-saved ones stay for leaf functions only.
     Promotion now also accepts `mov`/`cmp` between a slot and %rax, %rcx or %rdx, `addq/subq/movq $imm` into a
     slot, and loads of pushed call arguments (`mov N(%rsp),reg`); a jump out of the function, or a `ret`
     without a `leave`, keeps callee-saved registers out. tests/fs/regalloc.cud adds ra_calls (accumulators
     live across calls) and ra_rec (recursion with locals live across both calls); `fs-opt-shape` also checks
     that ra_calls uses %rbx. Kernel frame accesses with the flag: 15,632 without it, 15,187 after step 1,
     11,515 after step 2. Most remaining ones are in functions with arrays, structs or `addr()`.
   - *Step 3 done (2026-11-12).* The kernel and kernel-next are built with `--fs-opt` (examples/kernel/build.cud
     and build.sh; tests/dwarf/run.sh builds its `-g` kernel the same way so dwarf/image-unchanged-by-g still
     compares like with like). Every top-level asm block and `@naked` function was audited for SysV register
     discipline (table in docs/SYSTEMS.md, "Kernel asm and --fs-opt"); one fix: `smep_probe`, which calls user
     bytes in ring 0 as a self-test, now saves rbp, rbx and r12–r15 around the call and restores them on the
     `smep_blocked` fixup path too. Kernel code 534,272 to 495,157 bytes (-7.3%), frame accesses in kernel.s
     16,312 to 11,860, div/idiv 150 to 25; 436 functions keep locals in callee-saved registers. The QEMU boot
     suite passes at O2 and O0 with this kernel (SMEP still blocks the probe: `SMEP blocks kernel exec: 1`).
   - *Step 3b done (2026-11-12): the native UEFI loader and the kernel modules.* examples/efi/build.cud
     (and build.sh) build loader.cud with `--fs-opt`, examples/modules/build.cud (and build.sh) build the
     seven test modules with it. Neither has hand-written asm. The loader's UEFI entry wrapper saves rdi/rsi
     (callee-saved under the Microsoft ABI) and firmware calls preserve rbx, rsi, rdi and r12–r15, a superset
     of what the SysV body keeps; modules call and are called by the kernel through the SysV ABI. Loader code
     11,171 to 10,195 bytes (-8.7%, div/idiv 8 to 0); module code 5,197 to 4,471 bytes (-14.0%), frame accesses
     112 to 11. Still without the flag: the user programs. A page-fault SIGSEGV handler that resumes the
     faulting instruction got rcx and r11 back clobbered (rt_sigreturn returned by sysret), and `--fs-opt`
     keeps leaf locals in r11 for whole loops. Fixed in the kernel: rt_sigreturn now leaves by iretq and
     restores both (lxsig checks it), which unblocks the user build.
   - *Step 3c done (2026-11-12): the user programs.* examples/user/build.cud (and build.sh) build all 25
     Incudela user programs (the 20 native ones and the 5 Linux-ABI tests) with `--fs-opt`. Their asm is naked
     syscall stubs that touch only caller-saved registers, and callers never keep a caller-saved register
     across a call. Code 175,859 to 168,467 bytes (-4.2%; sh 13,070 to 12,329, lxfs 14,008 to 13,334), frame
     accesses 4,867 to 3,891 (-20%), asm lines 59,362 to 54,842. Every Forge-compiled image now uses the
     flag; BusyBox is C (gcc, musl) and is unaffected.
   - *Step 4a done (2026-11-12): promotion next to frame aggregates.* The first slice of step 4. Before, any
     `lea` of the frame (an array or struct local, `addr()` of a local) or any other `%rbp` form kept the whole
     function in memory. Now, in a function with no unsafe operation (`fs_unsafe_op` never called, so no raw
     load/store, int-to-pointer cast or inline asm can reach the frame), such a line pins every frame offset it
     names, and the pass promotes only offsets that are scalar locals (8 bytes or narrower, recorded by
     `fs_newlocal`; scopes never reuse an offset) and not pinned. A struct field or array word read as an
     8-byte slot is never a local's offset, and safe code cannot index past an aggregate (bounds checks), so
     the promoted slots are reached only through the rewritten lines. `rep movsb`/`rep stosb` (array
     parameter copies, zero fills) are accepted and take rsi/rdi out of the free set; `lock`, `xchgq`,
     `pause`, `mfence`, `rdtsc` and `cld` join the whitelist (they name only explicit operands or rax/rcx/rdx,
     which are never allocated). Code built without `--fs-opt` is byte-identical (all tests/fs programs and
     the kernel compared). tests/fs/regalloc.cud adds ra_arr (frame array, frame refs 25 to 11), ra_cpy
     (array parameter copy plus a struct, 29 to 20) and ra_mix (`addr()` of one local, 18 to 4; that local
     stays in memory), each checked by `fs-opt-shape`. Kernel: frame accesses 12,040 to 11,553 (-4.0%) in 40
     functions (sys_fork 79 to 23, smp_init 57 to 23, acpi_init 64 to 34), none worse; code 566,100 to
     566,260 bytes (+160, callee-saved saves). Loader frame accesses 401 to 388; user programs and modules
     unchanged (their aggregate functions use unsafe operations). Reseed.
   - *Differential fuzzing for `--fs-opt` (2026-11-12).* Gate before any further step 4 work. tools/fsfuzz.cud
     generates random, well-typed, terminating freestanding programs aimed at what the pass rewrites (up to 8
     parameters, more scalar locals than free registers, `w: i64[4]` array parameters, frame arrays, `addr()` of
     a local, calls to earlier functions, nested loops with read-only counters, wrapping arithmetic, shifts,
     narrow casts, division by constants and by positive variables, signed and unsigned compares) and builds each
     four ways: O2, -O0, `--fs-opt`, -O0 `--fs-opt`. The stdout plus exit status of all four must match; any diff
     fails and prints the four results (`--keep` leaves the sources and binaries in build/fsfuzz). run_tests runs
     `fs-opt-fuzz` (seed 1, 20 programs, about 10 s). Before landing: seeds 1-4, 305 programs (about 61,700
     lines), 0 diffs; in the `--fs-opt` builds frame accesses drop (seed 7, program 0: 738 to 619) and rbx/r12/r8
     are allocated, so promotion is exercised. See docs/tools-fsfuzz.md.
   - *Step 4b done (2026-11-12): liveness-based register sharing, opt-in `--fs-live`.* Steps 1-2 give each
     promoted slot its own register for the whole function, so functions with more promotable slots than free
     registers kept the rest in memory. `--fs-live` (implies `--fs-opt`) builds a control-flow graph over the
     finished lines (fall-through, `jmp`/`jcc` to `.LF` labels, `ret` ends a path), runs backward liveness per
     slot, and gives each slot the interval of positions where it is live on entry or written (dead writes
     included). A linear scan, most-used slot first, puts each slot in the first free register none of whose
     slots' intervals overlaps its own; a callee-saved register's first slot still needs 3 uses, later ones share it
     for free. A jump out of the function or to an unknown label falls back to step 1-2 allocation. Rewrite,
     callee-saved saves and every eligibility rule are unchanged, and code built without the flag is
     byte-identical (the kernel with and without `--fs-opt` compared against the previous compiler). Tests: every
     tests/fs program again under `--fs-live` (`PASS fs-live ...`, 22 programs); tests/fs/regalloc.cud adds
     ra_seq (14 phase-local scalars plus 2 long-lived ones, 16 slots for 11 registers): frame accesses 103 plain,
     33 with `--fs-opt`, 0 with `--fs-live` (`fs-live-shape`); tools/fsfuzz.cud now builds six ways (adds
     `--fs-live` and -O0 `--fs-live`): seeds 1-6, 480 programs (98,151 lines), 0 diffs. Kernel frame accesses with
     the flag 11,975 to 11,125 (-7.1%), compile 0.77 s. Next: SSA values for the stack-machine temporaries
     (push/pop and %rax/%rcx chains).
   - *Step 4b kernel switch (2026-11-12).* The kernel and kernel-next are built with `--fs-live`
     (examples/kernel/build.cud and build.sh; tests/dwarf/run.sh builds its `-g` kernel the same way). It uses
     the registers and eligibility rules of steps 1-2, so the step 3 asm audit covers it unchanged. Kernel text
     596,784 to 595,024 bytes, frame accesses in kernel.s 11,975 to 11,125. The QEMU boot suite at O2 and O0 is
     the test. The loader, modules and user programs stay on `--fs-opt` for now.
   - *Step 4c done (2026-11-12): stack temporaries into registers, opt-in `--fs-temps`.* The stack machine
     pushes every call argument and every left operand, so after step 4b most of the remaining memory traffic
     was `push %rax`/`pop` pairs and `(%rsp)` reloads. `--fs-temps` (implies `--fs-live`) runs two more text
     passes after the step 2 peephole. `fs_tmp_peep` turns a constant loaded into %rcx through the stack
     (`push %rax; xor %eax,%eax` or `movabs $N,%rax; mov %rax,%rcx; pop %rax`) into one `xor %ecx,%ecx` or
     `movabs $N,%rcx`. `fs_tmp_args` finds each call whose 1-6 argument pushes are later reloaded into distinct
     argument registers, and writes each argument straight to its register (`mov %rax,REG`), dropping the
     pushes, the alignment pad, the reloads and the `add $T,%rsp`. It only fires when T is 8n plus pad and a
     multiple of 16, the region between the pushes and the call holds only whitelisted instructions (20 mnemonics
     that touch no memory through %rsp) or balanced push/pop pairs, has no label, jump, call or %rsp use, and
     nothing after an argument's push names that argument's register; anything else keeps the stack form.
     Code built without the flag is byte-identical (the kernel plain, with `--fs-opt` and with `--fs-live`,
     compared against the previous compiler). Tests: every tests/fs program again under `--fs-temps` (`PASS
     fs-temps ...`, 22 programs, O2 and -O0); tests/fs/regalloc.cud ra_rec has `(%rsp)` operands under
     `--fs-live` and none under `--fs-temps` (`fs-temps-shape`); tools/fsfuzz.cud now builds eight ways (adds
     `--fs-temps` and -O0 `--fs-temps`): seeds 1-6, 480 programs (98,151 lines), 0 diffs. On the kernel with
     the flag: instructions 147,046 to 125,711 (-14.5%), `push %rax` 13,117 to 3,912, `(%rsp)` operands 8,204
     to 899. The kernel is not switched yet (a separate commit, gated by the QEMU suite). Next: a real SSA value
     numbering for the remaining %rax/%rcx chains.
   - *Step 4c kernel switch (2026-11-12).* The kernel and kernel-next are built with `--fs-temps`
     (examples/kernel/build.cud and build.sh; tests/dwarf/run.sh builds its `-g` kernel the same way). It only
     rewrites compiler-generated pushes of call arguments and constants, never a hand-written asm line (asm
     mnemonics outside the 20-entry whitelist end the region), so the step 3 asm audit covers it unchanged.
     Kernel .text 529,365 to 465,056 bytes (-12.1%), `(%rsp)` operands in kernel.s 8,204 to 899, `push %rax`
     13,117 to 3,912. The QEMU boot suite at O2 and O0 is the test. The loader, modules and user programs stay
     on `--fs-opt` for now.
   - *Step 4d (2026-11-16): SSA values for the scratch registers, opt-in `--fs-ssa`.* After step 4c most of the
     remaining instructions are %rax/%rcx chains: a constant loaded into %rcx for one ALU op or compare, and every
     comparison materialized as 0/1 (`setCC %al; movzbl %al,%eax`) and tested again before the branch.
     `--fs-ssa` (implies `--fs-temps`) runs after fs_tmp_args. `fs_ssa_run` builds each function's control-flow
     graph the way fs_lv_build does (it gives up on a function with a jump outside its `.LFn` labels), gives each
     instruction read/write semantics for the ten tracked registers (rax, rcx, rdx, rsi, rdi, r8-r11 and the
     flags; partial-register writes also read; `ret` reads rax and rdx, a call reads the argument registers its
     own set-up wrote; any mnemonic without semantics, any non-`.L` column-0 line and any jump inside a
     multi-line entry is a barrier that reads and writes everything), and computes SSA value numbers with phis
     at join points by a forward fixpoint. `fs_ssa_check` verifies every use names exactly one reaching
     definition or a phi of that register, and the function is left alone if it does not. Use counts come from
     instruction reads plus the operands of live phis. `fs_ssa_fold` then rewrites, when the counts allow: `mov
     $N,%rcx` + `OP %rcx,%rax` (add, sub, and, or, xor, cmp; N an imm32) into `OP $N,%rax`; `xor %ecx,%ecx` +
     `cmp %rcx,%rax` into `test %rax,%rax`; `setCC %al; movzbl %al,%eax; test %rax,%rax; je/jne L` into `jNCC
     L`/`jCC L`; up to four rounds, since a fold can expose another. Code built without the flag is
     byte-identical (the kernel default, `--fs-opt`, `--fs-live`, `--fs-temps` compared against the previous
     compiler). On the kernel with the flag, against `--fs-temps`: instructions 134,600 to 120,544 (-10.4%),
     `movzbl %al,%eax` 5,145 to 2,266, `mov $N,%rcx` 5,926 to 2,037, `xor %ecx,%ecx` 1,779 to 249; compile time
     0.7 to 1.8 s; `--unsafe-report` unchanged. Tests: tests/fs/ssa.cud (compares, immediates, values across
     joins, loops); every tests/fs program under `--fs-ssa` (`PASS fs-ssa ...`, 23 programs, O2 and -O0);
     `fs-ssa-shape` (ssa_cmp has `movzbl` and `mov $N,%rcx` under `--fs-temps`, none under `--fs-ssa`);
     tests/optgate under `--fs-ssa`. Landing rule: optcov group `fs-ssa (fs_ssa_*)`, `optcov --check` green;
     fsfuzz builds ten ways and `--combos` 72 flag sets; `fsfuzz --combos` seeds 1-3 x 25 programs (10,800 builds,
     4,236 distinct assemblies) and the ten-way form seeds 1-6 x 80: 0 differ; `optcov --check` OK (fs-ssa
     144/166 blocks, 52 allowed never-hit overall). The kernel stays on `--fs-temps`; switching it
     is a separate QEMU-gated commit.
   - *Step 4d kernel switch (2026-11-16).* The kernel and kernel-next are built with `--fs-ssa`
     (examples/kernel/build.cud and build.sh; tests/dwarf/run.sh builds its `-g` kernel the same way). Like every
     `--fs-*` pass it never runs on a function with an `asm()` statement (fs_regalloc is skipped for those), and
     `@naked` functions and top-level asm blocks are not compiled code, so the step 3 asm audit covers it
     unchanged. Kernel .text 508,896 to 457,536 bytes (-10.1%), instructions in kernel.s 134,600 to 120,544
     (-10.4%); `--unsafe-report` unchanged (168 functions, 0 blocks, 659 ops, 7 top-level asm blocks). Before the gate, `tests/os/run.sh` at O2 with the
     `--fs-ssa` kernel: 45 PASS, 0 FAIL (BIOS, SMP1, IOMMU, UEFI, GPT loader, kexec, old-to-new kexec, drivers,
     boot policy, ForgeFS, object store, desktop, DWARF/gdb); the gate runs it at O2 and O0.
     The loader, modules and user programs stay on `--fs-opt` for now.
   - *Step 4e (2026-11-16): dead register writes, under `--fs-ssa`.* The first use of the SSA use counts beyond
     the step 4d pattern folds. `fs_ssa_dead` runs after `fs_ssa_fold` in every round and deletes a reached
     one-instruction line that only writes one tracked register from an immediate or another tracked register
     (`mov`/`movq`/`movabs` to a 64-bit register, `movl` to a 32-bit one, `movzbl %al,%eax`, `xor %eR,%eR`), when
     no instruction and no live phi reads that value and, for `xor`, nothing reads its flags. Lines with a memory
     operand stay (a load can fault). Deleting a line only removes uses, so the same round's counts stay a safe
     upper bound for the folds. Code built without `--fs-ssa` is byte-identical (the kernel default, `--fs-opt`,
     `--fs-live`, `--fs-temps` compared against the previous compiler). On the kernel: instructions 120,544 to
     119,967, .text 457,536 to 456,237 bytes; the deleted lines are 470 `xor %eax,%eax` (a dropped call result
     overwritten by the implicit return value), 77 `mov %rdx/%rcx,%rax` and 29 `mov %rax,%rN`. Tests:
     tests/fs/ssa.cud gains ssa_dead (returns from inside a loop) and ssa_drop (a dropped call result at the end of
     a function; `fs-ssa-dead-shape`: two `xor %eax,%eax` under `--fs-temps`, one under `--fs-ssa`); every
     tests/fs program under default, `--fs-temps`, `--fs-ssa`, `-O0 --fs-ssa` and `-g --fs-ssa`: 23/23. Landing
     rule: `optcov --check` OK (fs-ssa 162/184 blocks, every new block hit, no new allow-list entry); `fsfuzz
     --combos` seeds 1-3 x 25 (10,800 builds, 4,236 distinct assemblies) and the ten-way form seeds 1-6 x 80:
     0 differ.
     Next: copy propagation, which the kernel's remaining `mov %rdi,%rax; mov %rax,%r9` pairs call for.
   - *Step 4f (2026-11-16): copy propagation, under `--fs-ssa`.* `fs_ssa_copy` runs in every round without a
     fold (so a line is never rewritten twice in one round). A reached one-instruction, register-only line
     `MN %rB,Y` (MN mov, cmp, test, add, sub, and, or, xor, imul) or, for cmp and test, `MN X,%rB`, whose %rB
     value is the copy written by `mov %rA,%rB` (both tracked 64-bit registers) while %rA still holds the value
     it had after that copy (same SSA value at the use), reads %rA instead; a `mov %rA,%rA` that results is
     deleted. Only operands the instruction reads and does not write are replaced, and the two registers hold
     the same 64-bit value there, so every replaced read is unchanged. The copy, now unread, is removed by step
     4e in the next round; a rewrite only adds reads of a value the copy already reads, so the round's counts stay
     a safe upper bound. Code built without `--fs-ssa` is byte-identical (the kernel default, `--fs-opt`,
     `--fs-live`, `--fs-temps` compared against the previous compiler). On the kernel: instructions 119,967 to
     118,980; the parameters of a leaf function are now compared and added in %rdi/%rsi/%rdx instead of
     through %r8-%r10 copies (tests/fs/ssa.cud ssa_copy: 31 to 20 instructions). Compile time of the kernel
     under `--fs-ssa` 2.0 to 2.7 s. More rounds than four gain 2 instructions on the kernel, so the cap stays.
     Tests: ssa_copy in tests/fs/ssa.cud and `fs-ssa-copy-shape` (%r8-%r10 under `--fs-temps`, none under
     `--fs-ssa`); every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa` and `--no-bounds
     --fs-ssa`: 23/23. Landing rule: `optcov --check` OK (fs-ssa 177/199 blocks, every new block hit, no new
     allow-list entry); `fsfuzz --combos` seeds 1-3 x
     25 (10,800 builds, 4,236 distinct assemblies) and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Step 4g (2026-11-16): the loader, modules and user programs built with `--fs-ssa`.* examples/efi,
     examples/modules and examples/user (build.cud and the reference build.sh, which tests/*-build compare)
     name `--fs-ssa` instead of `--fs-opt`, so everything Incudela boots is built like the kernel. They have no
     hand-written asm outside the audited user routines, and no `--fs-*` pass runs on a function with an `asm()`
     statement. Instructions: loader 2,974 to 2,205 (-25.9%), user programs 54,504 to 41,100 (-24.6%), modules
     1,259 to 995 (-21.0%); incudelax64.efi 13,312 to 10,752 bytes, user ELFs 757,008 to 736,528 bytes. Those
     are the gains of `--fs-live`, `--fs-temps` and `--fs-ssa` together, since these images skipped steps 4b and
     4c. tests/modules-build, user-build, efi-build and kernel-build pass (build.cud and build.sh agree,
     reproducible images, O0). Before the gate, `tests/os/run.sh` at O2 with these
     images: 45 PASS, 0 FAIL (UEFI loader boots, modules, user programs, Linux ABI, desktop, kexec).
   - *Step 4h (2026-11-16): the callee-saved registers in the SSA form, under `--fs-ssa`.* %rbx and %r12-%r15
     (with their 32-, 16- and 8-bit names) are tracked registers like the nine scratch and argument ones; a
     position now has 16 slots (registers 0-13, slot 14 unused, the flags in slot 15; value ids p * 16 + r,
     16n + r, 16n + 16 + p * 16 + r). A call writes only the nine caller-saved registers and the flags (SysV:
     the callee preserves the others) and reads only its argument set-up as before; a `ret` reads %rax, %rdx and
     the five callee-saved registers, so the restores fs_ra_save puts before `leave` are never dead; a barrier
     still reads and writes every slot. Copy propagation (step 4f) and dead-write removal (step 4e) then apply to
     them unchanged: a value kept in %rbx across a call is read from %rbx instead of through a `mov %rbx,%rax` or
     `mov %rbx,%rcx` copy. %rbp, %rsp and %rip stay untracked. Code built without `--fs-ssa` is byte-identical
     (the kernel default, `--fs-opt`, `--fs-live`, `--fs-temps` compared against the previous compiler). On the
     kernel: instructions 118,980 to 117,427 (-1.3%); `mov %rbx,%rax` 2,415 to 1,957, `mov %r12,%rax` 1,202 to
     911, `mov %r13,%rax` 703 to 501, `mov %rax,%rdi` 5,013 to 4,474; .text of kernel.cud alone 453,291 to
     448,587 bytes. Compile time of the kernel under `--fs-ssa` 2.7 to 4.7 s (wider tables and more phis; the
     merge fixpoint is still a plain repeat-until-stable sweep). Tests: ssa_keep in tests/fs/ssa.cud (three
     values kept across two calls) and `fs-ssa-callee-shape` (`mov %rbx/%r12/%r13,%rcx` under `--fs-temps`,
     none under `--fs-ssa`); every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `--fs-ssa --fs-opt` and
     `--fs-ssa --fs-temps`: 23/23. Landing rule: `optcov --check` OK (the five verifier allow-list entries
     renamed to the 16-slot ids, no new entry); `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds
     1-6 x 80: 0 differ.
   - *Step 4i (2026-11-16): single-use moves retargeted, under `--fs-ssa`; the start of SSA-based allocation of
     the temporaries.* `fs_ssa_retarget` runs after step 4e in every round without folds or copy rewrites. A
     reached one-line move `MN S,%rA` (MN in FS_SSMOV: mov, movl, movzbl, movslq, lea and the other extending
     moves; a full 64- or 32-bit destination register) whose fall-through successor is `mov %rA,%rB`, where
     that copy is the only read of the %rA value (use count 1, phis included), becomes `MN S,%rB` (`%eB` for
     a 32-bit destination, which zero-extends exactly like the copy did) and the copy is deleted; a move that
     would become `mov %rB,%rB` goes too. S is still read before the write, nothing reads the %rA value that is
     no longer written, %rB holds the same value from the same place on, and no move touches the flags. Running
     after step 4e, which only empties lines, keeps the round's tables valid for the two lines. Code built
     without `--fs-ssa` is byte-identical. On the kernel: instructions 117,427 to 115,086 (-2.0%; `mov %rax,%rdi`
     4,474 to 3,535), .text of kernel.cud alone 448,587 to 441,355 bytes; the commonest results are
     `mov $N,%rsi`, `mov N(%rbp),%rdi` and `mov (%rax),%rcx`. Compile time of the kernel under `--fs-ssa` 4.7 to
     5.2 s. Tests: ssa_move in tests/fs/ssa.cud (a frame load and a constant moved straight into %rdi/%rsi) and
     `fs-ssa-retarget-shape` (the move-then-copy pairs under `--fs-temps`, none under `--fs-ssa`, at O2 and O0);
     every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa`, `--no-bounds --fs-ssa` and
     `--fs-ssa --fs-opt`: 23/23. Landing rule: `optcov --check` OK (every new block hit, no new allow-list
     entry); `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Step 4j (2026-11-16): temporaries allocated over straight-line ranges, under `--fs-ssa`.* fs_ssa_retarget
     now takes a range instead of one line: for a reached copy `mov %rA,%rB` at position c it walks back over
     at most FS_SSCH (24) one-line entries (no label, jump or multi-line entry) to the nearest move `MN S,%rA`
     (FS_SSMOV, a full 64- or 32-bit destination) at w. The range is computed in %rB when every %rA value written
     in [w, c) is read only inside (w, c] (its use count, phis included, equals the reads counted there), w does
     not write %rB, no line after w reads or writes %rB, and every line after w that touches %rA is an
     FS_SSCHM instruction (moves, add/sub/and/or/xor, cmp/test, imul, neg/not, shifts by an immediate) naming
     it only as %rA or %eA: w's destination and those names become %rB/%eB and the copy is deleted (step 4i is
     the range of one line). %rB's old value is read by nothing from w on, %rA keeps the value it had before
     w (nothing in the range read it and nothing after reads the range's values), no instruction has an implicit
     %rA operand, and the flags are computed by the same instructions. A range never reaches back over an earlier
     rewrite of the same round. Code built without `--fs-ssa` is byte-identical. On the kernel: instructions
     115,086 to 112,737 (-2.0%), `mov %rax,%rdi` 3,535 to 3,119, `mov %rax,%rbx` 805 to 394 (a counter in
     %rbx is now incremented with `add $1,%rbx` instead of `mov %rbx,%rax; add $1,%rax; mov %rax,%rbx`), .text
     of kernel.cud alone 441,355 to 434,491 bytes; compile time unchanged (2.4 s). Tests: ssa_range in
     tests/fs/ssa.cud and `fs-ssa-range-shape`; every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g
     --fs-ssa`, `--no-bounds --fs-ssa` and `--fs-ssa --fs-opt`: 23/23; the step 4f, 4h and 4i shape checks
     still pass. Landing rule: `optcov --check` OK, two new allow-list entries (defensive: a read of %rA after
     w outside the range, and a one-operand FS_SSMOV line, neither of which the straight-line range or the code
     generator produces); `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Step 4k (2026-11-16): phi-crossing temporaries measured; ranges may start at `xor %eA,%eA`, under
     `--fs-ssa`.* The planned step was temporaries whose range crosses a label (values that meet in a phi). It
     was implemented as a range whose start lies before a label with every predecessor's value moved into %rB,
     and it never fired: 0 rewrites on the kernel and no output difference on 63 sources (tests/fs,
     tests/optgate, examples/user, examples/efi, examples/modules). In this code generator a value that lives
     across a label is a local, which fs_ra already keeps in a register; the only temporary that crosses a
     label is the flags of an `and`/`or` condition. That code was removed rather than landed untested. What the
     ranges did miss is a zeroing start: a constant 0 is loaded with `xor %eax,%eax` and then copied out, which
     FS_SSMOV does not match. fs_ssa_rng (factored out of fs_ssa_retarget, with fs_ssa_rngdo doing the rewrite)
     now also accepts `xor %eA,%eA` as the start when nothing reads the flags it sets (no df on the copy's
     register) and rewrites it to `xor %eB,%eB`; a mark per position replaces the old last-write bound, so a
     range never includes a line rewritten earlier in the same round. Code built without `--fs-ssa` is
     byte-identical. On the kernel: instructions 112,737 to 112,268 (-0.4%), `xor %eax,%eax` followed by
     `mov %rax,%rN` 749 to 274, `xor %ebx,%ebx` 76 to 258, .text of kernel.cud alone 434,491 to 433,131 bytes;
     compile time unchanged (2.3 s); unsafe report 168 functions / 0 blocks / 659 ops / 7 asm blocks. Tests:
     ssa_range in tests/fs/ssa.cud (its s and i start at 0, now zeroed in their own registers) and
     `fs-ssa-zero-shape` (the zero-then-copy pair under `--fs-temps`, none under `--fs-ssa`, at O2 and O0);
     every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa`, `--no-bounds --fs-ssa` and
     `--fs-ssa --fs-opt`: 23/23; the step 4f, 4h, 4i and 4j shape checks still pass. Landing rule: `optcov
     --check` OK, four allow-list entries replacing step 4j's one in fs_ssa_retarget (two defensive ones in
     fs_ssa_rng, one carried over; a defensive one in fs_ssa_ren; and its 32-bit rename of %rA inside a range,
     which no compiled program produces); `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80:
     0 differ. Next: stack round-trips (`push`/`pop`) of nested-call arguments.
   - *Step 4l (2026-11-17): `push`/`pop` round-trips kept in registers, under `--fs-ssa`.* The stack machine saves
     the left operand of a nested expression (call arguments included) with `push %rax` and takes it back with
     `pop %rB` once the right one is computed. fs_ssa_pushpop takes each reached `pop %rB` and fs_ssa_ppa walks
     back over at most FS_SSPP (32) one-line, reached lines that fall through (no label, jump, call, return,
     `leave`, line naming %rsp/%esp/%sp, or line fs_ssa_line does not understand) to the `push %rA` that matches
     it, keeping balanced inner pairs as they are. fs_ssa_ppt picks the register T that holds the value
     meanwhile: one no line strictly between reads or writes, tried as %rB (the pop overwrites its old value),
     then %rA (it keeps the value itself), then a caller-saved register whose value at the push has no use at all
     (its SSA use count, live phis included, is 0). The push becomes `mov %rA,%rT` and the pop `mov %rT,%rB`,
     each dropped when it would copy a register to itself (`push %rax ... pop %rax` with %rax untouched
     disappears). Moves change no flags; nothing in the range addresses the stack, so no other access moves; no
     call is inside, so the alignment at every call is unchanged. It runs in fs_ssa_retarget's round on the same
     marks, so a position either pass rewrote is in no other range (a retargeted range writes its register
     before reading it and so adds no read of a value live at a push). Code built without `--fs-ssa` is
     byte-identical. On the kernel: instructions 112,268 to 109,854 (-2.2%), `push %rax` 4,170 to 2,154, pops
     3,365 to 1,349 (`pop %rax` 2,673 to 1,101). .text of kernel.cud grows 433,131 to 433,951 bytes (+0.2%):
     `push`/`pop` are one byte each and a register move is three, so this trades size for the store/load
     round-trip through the stack. Compile time 2.7 to 2.9 s (median of five runs; more functions now use all four rounds);
     unsafe report unchanged (659 ops). The four-round cap limits it: at eight rounds the kernel is 108,520
     instructions but compiles in about 4.0 s. A timed build (not committed) splits fs_ssa's 3.1 s at eight
     rounds into table build 25%, reaching definitions 19%, the verifier 13%, use counts 7%, live phis 16% and the
     rewrites 21%, so no single phase dominates. Tests: ssa_push in tests/fs/ssa.cud (nested operands and two
     indexed loads) and `fs-ssa-pushpop-shape` (fewer pops under `--fs-ssa` than under `--fs-temps`, at O2 and
     O0); every tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa`, `--no-bounds --fs-ssa` and
     `--fs-ssa --fs-opt`: 23/23; the step 4d-4k shape checks still pass. Landing rule: `optcov --check` OK (every
     new block hit, no new allow-list entry); `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x
     80: 0 differ. Next: cheaper rounds (fewer table rebuilds), then a higher round cap.
   - *`--fs-ssa` rounds cheaper again (2026-11-17, after step 4o).* Steps 4m-4o brought the kernel's `--fs-ssa`
     compile back to 3.1 s. Sampled (a ptrace profiler on the box, not committed): the line parse of every
     round, the merge sweeps and the verifier inside fs_ssa_run, and outside it fs_regalloc's own line checks,
     which counted the newlines of every line one character at a time and ran 44 substring searches per line
     for 18 distinct register names. Now: fs_ssa_run keeps a row cache per out[] entry (scratch tables 15-19:
     the entry it was computed for, compared by identity, so an entry a pass rewrote is parsed again; its kind;
     read and write masks; the jump's label number or the call's operand), so an unchanged line is not parsed
     again in the next round (a call and a `setCC %al` / `movzbl %al,%eax` pair, which depend on their
     neighbours, are still worked out every round); a merge into a position with one predecessor takes the
     value without the phi tests (it never gets a phi since 51b964b); fs_ssa_phis sets its live marks only for
     the phi half of the value space, the only half it reads; fs_ssa_check masks instead of dividing;
     fs_regalloc finds the newline with find_char and searches each register name once (FS_RAX), skipping
     those already ruled out. The kernel's `--fs-ssa` compile: 3.14 to 2.30 s (median user time of seven
     interleaved runs; 3.02 to 2.23 s best). The output is byte-identical: the kernel, and 64 sources under
     `--fs-ssa` and `-O0 --fs-ssa`, and under no flag, `-O0`, `--fs-opt`, `--fs-live` and `--fs-temps`.
     Landing rule: `optcov --check` OK (allow-list entries moved to the cached jump check and fs_ssa_row; the
     merge's one-predecessor branch, now never taken, removed); fsfuzz as for every optimizer commit.
   - *`--fs-ssa` rounds cheaper (2026-11-17).* Timed by phase (a `__clock` build, not committed): of the
     kernel's SSA time, building the tables took about a third, half of it allocating the per-line tables (16
     or 32 entries a line, fresh every round of every function) and the rest parsing each line again; the merge
     sweeps over every position until stable took a fifth, and the verifier an eighth. Now: fs_ssa_buf keeps
     the scratch tables from one round and function to the next (growing them when needed, clearing only what
     is used, and not at all for tables that are written in full first); fs_ssa_linec caches what a one-line
     entry reads and writes by its text (two 16-bit masks), since that depends on the text alone and most
     lines come back unchanged every round; the merge sweeps skip positions none of whose entries changed since
     they were last processed (dq), which makes the same updates in the same order, so the phis are the same
     (a worklist in another order would place some phis differently and was not used); fs_ssa_check and the
     merge loop hoist their index arithmetic and read the outgoing value inline. The kernel's `--fs-ssa`
     compile: 2.31 to 1.74 s (median user time of seven runs), fs_ssa's share about 1.9 to 1.15 s. The output
     is byte-identical: the kernel, every tests/fs and tests/optgate program, examples/user, examples/efi and
     examples/modules (64 sources) under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa`, `--no-bounds --fs-ssa`,
     `--fs-ssa --fs-opt`, `--fs-temps` and no flag. Landing rule: `optcov --check` OK (the verifier's
     allow-list entries renamed to the hoisted lines, the edge check split into its two successors).
   - *Eight `--fs-ssa` rounds (2026-11-17).* A function's SSA form is rebuilt and rewritten until a round changes
     nothing, at most FS_SSRND rounds (was four, the 4d loop). Four cut the later rewrites short: at four the
     kernel's step 4l pairs and the dead writes their folds leave were still being found (a `push %rax ... pop
     %rax` around an indexed load stayed in tests/fs/ssa.cud's ssa_push). On the kernel: eight rounds give
     108,520 instructions (four 109,854, sixteen 108,430), pops 1,349 to 1,049, `push %rax` 2,154 to 1,854,
     register-to-register moves 18,317 to 17,583, .text of kernel.cud 433,951 to 431,167 bytes; compile 1.74 to
     2.36 s (median user time of seven runs; wall about 2.4 s), under the 2.9 s it took before the rounds got
     cheaper. Code built without `--fs-ssa` is byte-identical; unsafe report unchanged (659 ops). Tests: every
     tests/fs program under `--fs-ssa`, `-O0 --fs-ssa`, `-g --fs-ssa`, `--no-bounds --fs-ssa` and `--fs-ssa
     --fs-opt`: 23/23; all eight fs-ssa shape checks at O2 and O0. Landing rule: `optcov --check` OK; `fsfuzz
     --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Where the kernel's moves and pops are (2026-11-17).* Of the 17,583 register-to-register moves under
     `--fs-ssa` (at 1aa0e7f): 5,138 copy %rax into an argument register in the straight-line run before a call,
     4,619 copy into %rax, 1,554 pass the arguments of the cold bounds-failure call, 990 are the prologue's
     `mov %rsp,%rbp`, 1,295 copy %rax into %rcx (617 of them before a `pop %rax`), 3,987 are other copies. Of the
     1,049 pops, 695 are `mov %rax,%rcx; pop %rax`, a binary operator taking its left operand back, 170 other
     `pop %rax` and 184 other registers. The moves are the larger and the call arguments their largest group.
   - *Step 4m, call arguments straight in their registers (2026-11-17).* fs_ssa_call counted %rax as read by
     every call whose straight-line run wrote it (the vector count `mov $n,%eax` of a variadic callee), so a
     value computed in %rax and copied to %rdi had two reads and step 4i/4j could not retarget it. The code
     generator writes %eax only when an argument goes in an %xmm register, right before the call; fs_ssa_novec
     checks the run for an %xmm write or a `mov $n,%eax`, and without one the call does not read %rax (a callee
     never takes an argument there; a variadic callee with no vector argument gets whatever %rax held before,
     as it did). On the kernel: 108,520 to 103,596 instructions (-4.5%), register moves 17,583 to 12,656, .text
     431,167 to 416,495 bytes (-3.4%); pops 1,049 to 1,052 (in tty_swap_to and sys_kexec a retargeted copy
     now shares a round with a push/pop pair that the old copy left alone). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged (659 ops). New test ssa_args and check fs-ssa-args-shape (also: the
     three vector counts in tests/fs/cabi_float.cud stay right before their calls). Landing rule: `optcov
     --check` OK; fsfuzz combos seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Step 4n, copy propagation through memory operands (2026-11-17).* Step 4f rewrote register-only lines, so an
     array store computed the address in %rax, copied it to %rcx, moved the value to %rax and stored
     `mov %rax,(%rcx)`. fs_ssa_cpline now also takes a one-line `MN X,Y` with a memory operand (MN in FS_SSCP or
     FS_SSMOV): fs_ssa_cpmem replaces each base or index register that holds a copy by the copy's source (they
     are only read), and for FS_SSCP the register X too (the value a store writes). The same conditions as step
     4f: the source still holds the value it had after the copy, at most one rewrite per line and round, and
     the use counts stay an upper bound. Over the rounds `mov %rax,%rcx; mov %rdx,%rax; mov %rax,(%rcx)` becomes
     `mov %rdx,(%rax)`. On the kernel: 103,596 to 102,244 instructions (-1.3%), register moves 12,656 to 11,296,
     .text 416,495 to 412,527 bytes; pops 1,052 to 1,056. Kernel `--fs-ssa` compile 2.4-2.8 s (median user
     time of seven runs, the same spread as 1aa0e7f on the same box). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged (659 ops). New check fs-ssa-mem-shape (ssa_move, with
     `--no-bounds` so -O0 has no bounds-check label between the push and pop). Landing rule: `optcov --check`
     OK; fsfuzz combos seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Fix, the SSA form inside loops (2026-11-17).* The value sweep of fs_ssa_run gave a position a phi of its
     own whenever its incoming value changed, also when the position has a single predecessor. In a loop the
     header's value first arrives from the entry and then turns into the header's phi, so every position after
     the header up to the next write got a phi of its own: the same register content had a different name at
     each line, and fs_ssa_cpsrc, which checks that a copy's source still holds the value it had at the copy,
     always failed inside loops (`mov %r8,%rax; cmp %rdi,%rax` stayed). A position with one predecessor (the
     function entry counts as one for position 0) now takes that predecessor's outgoing value each time it
     changes; joins work as before. The sweeps still end (every reached cycle passes a join, whose entry
     changes at most twice) and fs_ssa_check still holds. On the kernel: 102,244 to 101,399 instructions,
     register moves 11,296 to 10,447, .text 412,527 to 410,143 bytes. Kernel `--fs-ssa` compile 2.6 s (median
     of five, 2.6 s before). Code built without `--fs-ssa` is byte-identical; unsafe report unchanged. New test
     ssa_lcopy and check fs-ssa-loop-copy-shape (its compares read the loop counters, no `cmp ...,%rax`).
   - *Step 4o, push/pop round-trips across failure paths (2026-11-17).* Of the 1,056 pops left after step 4n,
     680 belonged to a round-trip (`push %rax`, the value of an array store or a binary operator's left operand;
     the address or right operand with its bounds check; `pop %rax`) that step 4l refused only because the
     bounds check's label sits in the range. fs_ssa_cold accepts such a label when its only predecessors are a
     conditional jump to it and a `ud2` right before it, and the lines between are straight-line, reached and
     unmarked with no push, pop or return: either the checked-ints trap (`jno L; ud2; L:`) or the bounds
     failure `...; sub $8,%rsp; call forge_bounds_fail; add $8,%rsp; ud2`. Control never comes back from that
     path, so the register T that keeps the value may be written there (it may not be read), and dropping the
     push makes the stack depth even, so the call's 8-byte alignment pad goes too (any other stack-pointer line
     or call refuses). Over the rounds most bounds-checked stores and indexed operands keep their value in a
     register. On the kernel: 101,399 to 99,001 instructions (-2.4%), pops 1,058 to 459, .text 410,143 to
     404,031 bytes. Kernel `--fs-ssa` compile 2.95 s (median of seven, 2.7 s for the fix alone and 2.8 s for
     c6191de on the same box: more functions use all their rounds). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged (659 ops). New test ssa_cold and check fs-ssa-cold-shape (no pad
     before its failure calls and one pop, around the `and`, a real join). One allow-listed optcov block, the
     refusal of a failure path that is not straight-line, which the code generator never emits.
   - *Step 4p, copies into %rax (2026-11-17).* Measured on the compiler after the cheaper rounds (output as at
     step 4o): 2,276 `mov %rS,%rax` lines in the kernel, by what follows them: 425 `mov $N,%rcx` (most before
     `imul %rcx,%rax` for an index scale, or `mul %rcx` for a constant division), 417 `add $N,%rax` (a field
     or element address), 224 `add %rcx,%rax`, 159 a bounds check's `cmp $N,%rcx`, 152 `push %rax` (a left
     operand kept across a call), 146 a `jmp` (a value flowing into a join). The copy is needed because those
     instructions read and write %rax in place. fs_ssa_raxc (in fs_ssa_fold, on consecutive entries, reached
     code) rewrites `mov %rS,%rax` (S a tracked register other than %rax) with the next line: `add $N,%rax`
     becomes `lea N(%rS),%rax` and `add %rT,%rax` becomes `lea (%rS,%rT),%rax` when the add's flags are read
     nowhere (lea sets none); `mov $N,%rcx; imul %rcx,%rax` becomes `imul $N,%rS,%rax` when that %rcx value is
     read only by the imul (the same product and flags); `push %rax` becomes `push %rS` when the push is the
     copy's only reader. The add and the imul read the copy and overwrite %rax, so they are its only reader.
     The rewrites need more rounds to finish (each one exposes copy propagation and moves into the copy's
     register), so FS_SSRND goes from eight to twelve; twelve rounds alone would give 98,669 instructions. On
     the kernel: 99,001 to 97,286 instructions (-1.7%), copies into %rax 2,276 to 1,360, register moves 10,451 to
     8,822, pops 459 to 437, .text 404,031 to 399,599 bytes. Kernel `--fs-ssa` compile 2.42-2.46 s against 2.84-2.95 s for
     f3450b7 in the same interleaved runs (2.26 to 2.60 s against the cheaper rounds alone in another set); under
     3 s either way. Code built without `--fs-ssa` is byte-identical; unsafe report unchanged (168 functions,
     659 ops). New tests ssa_rax (lea for `a + 5` and `a + b`, three-operand imul, and `a - 9` and `b + b`) and
     ssa_rpush (left operands pushed across calls), checks fs-ssa-rax-shape and fs-ssa-rpush-shape. Left: copies
     before `mul %rcx` (constant division), shifts by %cl, bounds checks and joins. Landing rule: `optcov
     --check` OK (no new allow-list entry; one entry removed, a 32-bit rename in fs_ssa_ren that is now hit);
     `fsfuzz --combos` seeds 1-3 x 25 and the ten-way form seeds 1-6 x 80: 0 differ.
   - *Step 4q, push/pop across calls and mul by a constant (2026-11-17).* Re-measured after step 4p: 437 pops
     left (171 of them asm stubs that push the argument registers around a `cld`/`lea (%rsp)` body, which the
     pass does not touch), and 1,360 copies into %rax of which about 190 feed `mov $N,%rcx; mul %rcx` with the
     mul's %rdx unread. Step 4q extends the step 4l push/pop rewrite across calls when each call's stack set-up
     is a pad `sub $8,%rsp`, optional loads of other slots, the call and `add $K,%rsp` (fs_ssa_ppg): a
     callee-saved register holds the value (the pushed register itself when it is one, else one the function
     saves in its prologue that is free in the range and dead after the pop), and removing the push drops each
     pad (fs_ssa_ppd). The same step folds `mov %rS,%rax; mov $N,%rcx; mul %rcx` into `imul $N,%rS,%rax` when
     no instruction before the next write of %rdx or a return reads %rdx (the low 64 bits match; `ret` names
     %rdx only for the verifier, so a text scan replaces the use count). A fix (own commit) stops fs_ssa_line
     marking `mul` as reading %rdx. On the kernel: 97,286 to 96,843 instructions, pops 437 to 410, copies into
     %rax 1,360 to 1,185, .text 399,599 to 397,855 bytes. Kernel `--fs-ssa` compile about 2.85 s (under
     3 s; 2.72 s for 727c9cd in the same interleaved runs). Code built without `--fs-ssa` is byte-identical;
     unsafe report unchanged. New test ssa_mul and check fs-ssa-mul-shape; ssa_ppcall for values across a call.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4r, shift by an immediate (2026-11-17).* Re-measured after step 4q: 1,185 copies into %rax, 410
     pops (171 asm stubs), and 428 of `mov $N,%rcx; shr|shl|sar %cl,%rax` — the largest remaining group.
     Step 4r folds that pair into `shr|shl|sar $N,%rax` when the %rcx value is read once and N is in 0..63
     (fs_ssa_shimm). On the kernel: 96,843 to 96,232 instructions, copies into %rax 1,185 to 1,072, moves
     8,633 to 8,401. Kernel `--fs-ssa` compile about 2.70 s (under 3 s). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged. New test ssa_shift and check fs-ssa-shift-shape.
     tests/optgate/shimm.cud covers fs_ssa_shimm's three-digit refuse; the `$-` / non-`$` guard is on the
     allow-list (codegen never emits `mov $-N,%rcx` before a %cl shift).
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4s, redundant test after and/or/xor (2026-11-17).* Re-measured after step 4r: 184 of
     `and ...,%rax; test %rax,%rax` (and/or/xor set ZF/SF/PF and clear CF/OF the same way). Step 4s
     deletes the test when the and/or/xor's flags were unread. On the kernel: 96,232 to 96,055
     instructions. Kernel `--fs-ssa` compile about 2.76 s (under 3 s). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged. New test ssa_andtest and check fs-ssa-andtest-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4t, sar immediate via rcx_lo and sub→lea (2026-11-17).* Re-measured after step 4s: 49 of
     `mov $N,%rcx; shr|shl|sar %cl,%rax` left (many with cnt>1 from a call heuristic) and 11 of
     `mov %rS,%rax; sub $N,%rax` with unread flags. Step 4t adds `fs_ssa_rcx_lo` (text scan after the
     shift, like `fs_ssa_mul_lo`) so shifts fold despite false %rcx uses, matches `sar` by mnemonic, and
     rewrites unread-flag `sub $N,%rax` after a copy into %rax as `lea -N(%rS),%rax` (skipping the int32
     min). On the kernel: 96,055 to 95,918 instructions, copies into %rax 1,074 to 1,056. Kernel
     `--fs-ssa` compile about 2.57 s (under 3 s). Code built without `--fs-ssa` is byte-identical; unsafe
     report unchanged. New test ssa_sar and check fs-ssa-sar-shape; fs-ssa-rax-shape requires a negative
     lea. The rcx-read branch of `fs_ssa_rcx_lo` is on the allow-list (defensive).
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4u, alu imm via rcx_lo (2026-11-17).* Re-measured after step 4t: 187 of
     `mov $N,%rcx; alu/cmp %rcx,%rax` still blocked by false %rcx use counts from later calls. Step 4u
     reuses `fs_ssa_rcx_lo` on the alu/cmp path (cnt==1 or text scan). On the kernel: 95,918 to 95,191
     instructions, copies into %rax 1,056 to 1,035. Kernel `--fs-ssa` compile about 2.56 s (under 3 s).
     Code built without `--fs-ssa` is byte-identical; unsafe report unchanged. New test ssa_aluimm and
     check fs-ssa-aluimm-shape. The rcx-read allow-list entry from step 4t is removed (now covered).
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4v, mul already in %rax (2026-11-18).* Re-measured after step 4u: 267 of
     `mov $N,%rcx; mul %rcx` with the multiplicand already in %rax (and 40 of `imul %rcx,%rax`).
     Step 4v folds those to `imul $N,%rax` when N fits a 32-bit immediate and the mul's high half is
     unread (`fs_ssa_mul_lo`), reusing rcx_lo for false %rcx use counts. On the kernel: 95,191 to 94,742
     instructions, copies into %rax 1,035 to 979. Kernel `--fs-ssa` compile about 2.73 s (under 3 s).
     Code built without `--fs-ssa` is byte-identical; unsafe report unchanged. New test ssa_mulrax and
     check fs-ssa-mulrax-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4w, and→test before setcc (2026-11-18).* Re-measured after step 4v: 61 of
     `and $N,%rax; setCC` where the and's value was unread. Step 4w rewrites the and as `test $N,%rax`
     (same ZF/SF/PF/CF/OF; %rax kept so copy propagation can drop a prior `mov %rS,%rax`). On the kernel:
     94,742 to 94,731 instructions, copies into %rax 979 to 958. Kernel `--fs-ssa` compile about 2.91 s
     (under 3 s). Code built without `--fs-ssa` is byte-identical; unsafe report unchanged. New test
     ssa_andset and check fs-ssa-andset-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4x, setCC/test/je→jCC (2026-11-18).* Re-measured after step 4w: 1,210 of
     `setCC %al; movzbl %al,%r32; test %r64,%r64; je|jne L` on the kernel (302 with a duplicate test).
     Folding when L begins with setCC or jCC is wrong: short-circuit and/or keeps `setne` at L that needs
     ZF from the test (ssa_cold). Step 4x folds only when L does not consume flags and neither edge's first
     insn reads the 0/1 (kernel use-counts are inflated by phis). On the kernel: 94,731 to 93,932
     instructions (~167 safe jCC folds plus ~302 duplicate tests dropped); compile about 2.73 s (under 3 s). Code built without `--fs-ssa` is
     byte-identical; unsafe report unchanged. Check fs-ssa-jcc-shape (ssa_cold keeps setl/setne).
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4y/4z, store-reload and add $0,%rsp (2026-11-18).* Re-measured after step 4x: 191 of
     `mov %rS,D(%rbp); mov D(%rbp),%rS` and 630 of `add $0,%rsp` after calls. Step 4y drops the reload
     (store kept). Step 4z drops the no-op add when the next non-label line does not read flags. On the
     kernel: 93,932 to 93,068 instructions; compile about 2.89 s (under 3 s). Code built without `--fs-ssa`
     is byte-identical. Checks fs-ssa-reload-shape and fs-ssa-add0-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4aa/4ab, imm/zero and lea/load through %rax (2026-11-18).* Re-measured after step 4z: 530 of
     `xor %eax,%eax; mov %rax,MEM`, 206 of `mov $N,%rax; mov %rax,MEM`, 62 of `mov $N,%rax; mov %rax,%rD`
     (most with cnt≠1), 42 of `lea ADDR,%rax; mov %rax,%rD`, and about 120 of `mov MEM,%rax; mov %rax,%rD`.
     Step 4aa folds a one-use zero or fit immediate through `%rax` into `movq $N,MEM` or `mov $N,%rD`.
     Step 4ab retargets a one-use `lea` or load into `%rD`. Left alone: setCC chains (~1043) until a
     flag-safe stop rule. On the kernel: 93,068 to 92,421 instructions; compile about 2.81 s (under 3 s).
     Code built without `--fs-ssa` is byte-identical. Checks fs-ssa-zstore-shape and fs-ssa-leamov-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4ac/4ad, imul and add/sub through %rax into %rD (2026-11-18).* Re-measured after step 4ab: 99 of
     `imul $N,%rS,%rax; mov %rax,%rD`, 16 of `imul $N,%rax; mov %rax,%rD`, 428 of `add %rS,%rax; mov %rax,%rD`,
     62 of `add $N,%rax; mov %rax,%rD`, 11 of `sub $N,%rax; mov %rax,%rD`, and 11 of `mov %rS,%rax; mov %rax,MEM`.
     Step 4ac retargets three-operand imul (and turns two-operand into three-operand into `%rD`) and stores
     `%rS` straight to MEM. Step 4ad turns unread-flag add/sub into `lea` into `%rD`. setCC chains were left
     for a flag-safe stop rule (step 4ae). On the kernel: 92,421 to 91,805 instructions; compile about 2.48 s (under 3 s).
     Code built without `--fs-ssa` is byte-identical. Checks fs-ssa-imuldest-shape and fs-ssa-addlea-shape.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4ae, setCC through-merge stop (2026-11-18).* Re-measured after step 4ad: 1,043 of
     `setCC; movzbl; test; je|jne L` still on the kernel because L begins with je/jne (short-circuit
     and/or merges). When L is `je F` (or `jne F` with matching sense), the test's ZF is still live at L,
     so jumping straight to F is the same as taking L's jCC. Step 4ae folds those to one `jCC F` (same
     polarity as step 4x). Merges that keep `setne` at L stay refused. On the kernel: 91,805 to 90,623
     instructions; compile about 2.47 s (under 3 s). Code built without `--fs-ssa` is byte-identical.
     Check fs-ssa-through-shape (ssa_andmerge); fs-ssa-jcc-shape still requires setne/setl in ssa_cold.
     Landing rule: `optcov --check`; fsfuzz as for every optimizer commit.
   - *Step 4af, unreachable lines after `jmp` (2026-11-19).* Re-measured after step 4ae against w222/cudc-base
     (90,924 kernel instructions at 859634a): the largest remaining group is 1,733 instructions straight after an
     unconditional `jmp` with no label in between (1,178 `jmp`, 555 `xor %eax,%eax`), left by the lowering of
     `break`/`continue`/`return` inside a branch (`jmp .LFa; jmp .LFb`) and of the value after a loop exit
     (`jmp .LFr; xor %eax,%eax`). Nothing can jump to such a line and nothing falls into it; step 4af deletes
     it when the SSA form never reached it either. Any label (also a function name or an asm block's numeric
     label), directive or multi-line entry ends the run, and only `jmp` starts one (code after `ud2` or `ret` is
     left alone). On the kernel: 90,924 to 89,193 instructions; compile about 2.31 s (base 2.40 s, under 3 s).
     Code built without `--fs-ssa` is byte-identical. Check fs-ssa-unreach-shape (ssa_brk).
   - *Step 4ag, `jmp` to the next label (2026-11-19).* Re-measured after step 4af: 1,495 `jmp .LFk` on the kernel
     have `.LFk:` among the labels straight after them (only `.LFn:` lines between; 968 before step 4af, which
     clears the never-run lines that sat between many of them), mostly an else arm or loop exit jumping to the
     merge or return label that follows. Falling through goes to the same place, so step 4ag deletes the jump.
     A directive (`.p2align` padding), instruction or other entry in between keeps it. On the kernel: 89,193 to
     87,642 instructions (90,924 to 87,642 for the batch); compile about 2.47 s (base 2.35 s, under 3 s). Code
     built without `--fs-ssa` is byte-identical. Check fs-ssa-jnext-shape (ssa_brk's return-label jump goes;
     no `jmp` to a following label anywhere in tests/fs/ssa.cud).
   - *Step 4ah, scaled index (2026-11-19).* Re-measured after step 4ag against w223/cudc-base (87,642 kernel
     instructions at 63be618): the largest remaining group is the checked index scale, `imul $8,%rcx,%rcx` followed
     by `add %rcx,%rax` (1,007) or by the `lea (%rax,%rcx),%rD` that step 4ad makes of that add (576) to form an
     element address. When the scaled value is read only by the `add` and its flags are unread, step 4ah puts
     the scale in the address: `lea (%rD,%rR,S),%rD` (step 4ab then retargets it as before), with S 1, 2, 4 or 8
     and %rR a four-letter name (%rax..%rdi, %r10..%r15);
     %rR then keeps the unscaled index, which nothing reads. On the kernel: 87,642 to 86,168 instructions
     (1,474 fewer); compile about 2.48 s (base 2.55 s, under 3 s). Code built without `--fs-ssa` is
     byte-identical. Check fs-ssa-scale-shape (ssa_idx).
   - *Step 4ai, address into the mov (2026-11-19).* Re-measured after step 4ah: the next group is a `lea ADDR,%rT`
     straight before a `mov` that goes through `(%rT)`: the element addresses step 4ah leaves (`lea (%rB,%rI,8)`)
     and field addresses (`lea N(%rB)`). When that lea's value is read only by the mov, step 4ai gives the mov the
     address itself (`mov (%rax,%rcx,8),%rax`, `mov %rsi,8(%rax)`) and deletes the lea (1,812 on the kernel: 1,295
     element addresses, 494 field addresses, 23 others); %rT keeps its old value, and lea sets no flags. Refused:
     %rip-relative addresses, a mov with a displacement of its own on `(%rT)`, and any other mention of T in the
     mov at any width except a full (64- or 32-bit) load into T. On the kernel: 86,168 to 84,336 instructions
     (87,642 to 84,336 for the batch, -3.8%); compile about 2.39 s (base 2.48 s, under 3 s). Two functions
     (tss_install 2 pairs, sha_compress 1) keep push/pop pairs they lost before: the extra fold rounds use up
     the 12-round limit (FS_SSRND) before the round in which fs_ssa_pushpop runs; 16 rounds would give 84,293
     (not changed here; the stop rule and its measured cost are documented in docs/SYSTEMS.md, "SSA stop rule",
     inv233). Code built without `--fs-ssa` is byte-identical. Check fs-ssa-memfold-shape (ssa_idx).
   - *Step 4aj, `ud2` ends a path (2026-11-19).* Re-measured after step 4ai against w224/cudc-base (84,336 kernel
     instructions at 3ea3a9f): 696 bounds checks still copy the index to %rcx (`mov %rB,%rcx; cmp $N,%rB`) and
     address the element through the copy. Copy propagation (steps 4f/4n) could not reach the use: the SSA form
     let `ud2` fall through, so the failure path's `lea .LFBn(%rip),%rcx` (the call's file argument) merged into
     the pass label as a phi. `ud2` traps and nothing resumes after it, so it now has no successor: the pass label
     has one predecessor, the copy reaches the address (`mov (%rax,%rbx,8)`) and the copy goes. Step 4o's cold
     path test (fs_ssa_cold) now expects the label's single predecessor. On the kernel: 84,336 to 83,521
     instructions; index copies 696 to 70. Compile user time about 2.53 s (base 2.37 s; more functions now need
     more fold rounds), under 3 s. sys_kexec, mod_load, od_open, ob_lrec and sh_comp keep 10 more push/pop pairs:
     the 12-round limit again (16 rounds would recover them but cost about 0.14 s, so not done). Code built
     without `--fs-ssa` is byte-identical. Check
     fs-ssa-trapend-shape (ssa_idx); fs-ssa-scale-shape and fs-ssa-memfold-shape now accept any index register.
   - *Step 4ak, constant index into the displacement (2026-11-19).* Re-measured after step 4aj: 406 scaled
     addresses `(%rB,%rcx,S)` take a constant index loaded just before (`mov $N,%rcx`, 298; `xor %ecx,%ecx`, 108),
     element N of an array whose bounds check the compiler already dropped. When that index is read only by the
     address (and the xor's flags are unread), step 4ak writes `N*S(%rB)` (`(%rB)` for 0) and deletes the load;
     the mov must name %rR nowhere else except as a full load into it. On the kernel: 83,521 to 83,106
     instructions (415 fewer, some through step 4ai folding the `lea` before it); 84,336 to 83,106 for the two
     steps. Compile user time about 2.39 s (base 2.32 s), wall about 2.46 s (base 2.37 s), under 3 s. Code built
     without `--fs-ssa` is byte-identical. Check fs-ssa-cidx-shape (ssa_cidx; --no-bounds, since at -O0 the
     kept bounds checks compare the constant too). fs-ssa-mem-shape (step 4n) now also accepts `N(%rB)`, still
     exactly 2 stores of %rdx.
   - *`--fs-ssa` compile time (2026-11-16).* Timed by phase (a `__clock` build of the compiler, not committed),
     the kernel's 3.2 s of the 4.5 s spent in fs_ssa went to fs_ssa_phis: its live-phi fixpoint swept every
     position and register until nothing changed, one sweep per link of a phi chain, and since step 4h values in
     callee-saved registers form long chains through the loops. It now runs on a worklist over each position's
     reached predecessors (built once per round), which reaches the same least fixpoint, so the output is
     unchanged: the kernel, every tests/fs, tests/optgate, examples/user, examples/efi and examples/modules
     source under `--fs-ssa`, `-O0 --fs-ssa` and `-g --fs-ssa` (192 compiles) are byte-identical to the previous
     compiler. Kernel compile time under `--fs-ssa` 5.5 to 2.2 s (best of three: 5.48 to 2.05 s), below the 2.7 s
     before step 4h.
   - *fsfuzz conditions (2026-11-16).* tools/fsfuzz.cud's generator now negates one condition in eight
     (`not (a < b)`) and joins two compares with `and`/`or` in another one in eight, so the 0/1 comparison values
     and short-circuit jumps that step 4d works on are in every fuzz run (the programs of every seed change). On
     the unchanged compiler: `fsfuzz --seed 1 --n 20` and `fsfuzz --combos --seed 7 --n 3` agree.
   - *Asm audit as a checked list (2026-11-12).* The step 3 audit table in docs/SYSTEMS.md ("Kernel asm and
     --fs-opt") is now a `- [x]` checklist covering the kernel and the user programs, and tests/asm-audit/run.sh
     keeps it complete: it lists every `@naked` function, every top-level `asm(...)` block (its `.globl` symbols,
     or its first label) and every ordinary function with inline asm, and fails on a routine missing from a
     checked line, an unchecked `- [ ]` line, a stale name, or any asm in examples/modules or examples/efi. The
     rewrite found one routine the table missed, `gdt_load` (cpu.cudi: far return to reload cs, rax only, and
     `lretq` keeps it out of the pass), and added the 15 user routines (syscall shims, `regs_kept`,
     `xmm_yield_check`, the lxthreads atomics, `tclone`). run_tests: asm-audit-kernel (31), asm-audit-user (15),
     asm-audit-stale, asm-audit-none.
2. Auto-vectorization of simple loops (SSE2/AVX2, now that the kernel saves xsave state), plus explicit `simd[T, N]` types.
3. `parallel for` over ranges and slices, with a work-stealing multicore runtime in both hosted and kernel modes. Test: speedup on 4 cores is ≥ 3× on bench kernels, with deterministic results.
4. Perf targets:
   - self-compile under 1 s;
   - bench parity with gcc -O2 on the bench suite (tracked in bench/).
   - *Status: tracking in place, targets not met yet.* `./cuditor bench run` (tools/bench.cud, docs/tools-bench.md)
     records the self-compile time and each bench against its native reference in bench/history.tsv.
     `./cuditor bench check` compares the newest record with bench/baseline.tsv: more than +25% fails.
     run_tests.sh checks the comparison logic on fixed records (tests/bench), never live timing.
     Record integrity (2026-11-12): records carry the full HEAD sha; `bench run` refuses a tree with uncommitted
     tracked changes (`--allow-dirty` records it marked `+dirty`); the three orphan records whose short shas are not
     in the repository (e42065b, 836c322, 207d8e7) are annotated `note=orphan`. tests/bench/tree.sh, 4 checks.
     The reference is rustc -O3 for now; a gcc -O2 column needs C bench sources, which the All-Forge rule keeps out.
     Baseline at 2aba6e2 (2026-11-11, shared box): self-compile 2354 ms; Forge/Rust run-time ratios
     fib 1.51, loop 1.31, strbuild 0.63, lists 0.70, floats 1.02, strops 1.05.
   - *Self-compile speedup 1 (2026-11-11): 2354 ms to 1560 ms (-34%).* Sampling the compiler showed about a fifth of
     its time in the GC, set off by `declare_locals` allocating two 32 KiB name lists for every function on every
     inference pass (6 passes over about 830 functions) and `scan_more` allocating a list per statement. Both now
     reuse module-level buffers; the generated code is byte-identical (69 test, tool and kernel sources compared).

## Phase 13 — Instant and declarative system
*Pillar: D.*
1. Fast boot: a parallel device init and boot-time budget tracked by the boot test (firmware handoff to shell ≤ 300 ms in QEMU).
2. Declarative system config (`system.cud`: users, apps, capabilities, services). It builds an immutable, content-addressed image with atomic A/B switch and rollback, still installed only under `\EFI\Incudela\`. Test: rebuilding the same config gives the same hash, and a rollback boots the previous image.
3. Secure Boot: shim or MOK signing (SYSTEMS.md item 9).

## Phase 14 — One computer across devices (signature feature 5)
*Needs Phase 8 networking and Phase 9 objects.*
- Authenticated, encrypted device mesh.
- Pooled object store with replication.
- Live process migration (serialise address space, fds, and capabilities, then resume on the other node).
- Test: two QEMU nodes; a running program migrates mid-computation and finishes with the same result; storage stays readable when either node is offline.

## Desktop and apps (track; its first steps, a windowed compositor with a terminal and a sandboxed windowed program, are pulled forward with Phase 8 graphics/input: see "Current execution order")
- Graphical desktop shell and apps run as sandboxed Forge programs with manifest capabilities.
- **Default browser: a Forge browser.** Grok is built in as a core AI layer, not an add-on: page summaries, form filling, and carrying out tasks for the user (each action shown and approved, capability-checked, reversible like Phase 15 plans). It renders pages with a ported open-source engine (Servo preferred), running sandboxed with network and storage only through granted capabilities.
- **Replaceable, not required.** The Forge/Grok browser is only the shipped default. A system default-app setting (per app type: browser, mail, editor, viewer, terminal, …, and per URL scheme / file type) lets users pick another default; other browsers install like any app; the Grok browser can be fully uninstalled (binaries, data, grants). No OS feature may hard-depend on it: links and intents resolve through the default-app setting, and the system works with no browser installed.
- **Forge replaces JavaScript (approved).** Goal: web and desktop apps written entirely in Forge, with no JavaScript. Plan entries only; no code yet:
  1. Forge WebAssembly backend: cudc emits wasm modules. Forge programs then run in the Grok browser and in any other browser.
  2. Browser/DOM bridge: typed Forge bindings to the DOM and web APIs (events, fetch, storage), capability-checked in the Forge browser.
  3. Flutter-style cross-platform UI toolkit in Forge: declarative widgets, layout and rendering. The same toolkit drives the Incudela desktop and the Grok browser (wasm + DOM/canvas).
  4. Plugin package manager: Forge packages plus C FFI natives (11.2 ABI), versioned and sealed, sandboxed through manifest capabilities.
- Tests (when built): switching the default browser routes links/intents to the new one; uninstalling the Grok browser leaves no files or grants behind and every boot/OS test still passes; the browser renders a reference page set to match golden screenshots; summary and form-fill tasks run against local fixture pages; the engine process is denied anything outside its manifest.

## Phase 15 — Intent layer with local AI (signature feature 6)
- A local model runs on the device (CPU SIMD, later the GPU backend). It turns intents into typed, capability-checked command plans over the object store and services.
- The user sees and approves plans, and every action can be reversed through rewind.
- Tests: an intent suite with expected plans, permission-denial cases, and an offline-only check (no network capability).

## Phase 16 — New targets (AArch64, GPU)
*Pillars: B, C.*
1. AArch64 backend plus UEFI on QEMU `virt` (PL011, GIC, generic timer), running the same boot-test suite (SYSTEMS.md item 8).
2. GPU backend (SPIR-V compute from `parallel for` kernels). Test: a vector-add and a matmul match the CPU results.
3. (The intent layer itself is Phase 15.)

---

**Execution order:** strictly one phase at a time: 1 → 2 (never reboot) → 3 → 4 → 5 → 6 (proven-safe programs) → 7 → 8 → 9 (object store) → 10 (private by design) → 11 → 12 → 13 → 14 (one computer) → 15 (intent + local AI) → 16.

Each phase is finished, tested, and committed before the next one starts. The signature features (phases 2, 6, 9, 10, 14, 15) sit right after the phases they depend on. Never-reboot comes first because restart-free updates build directly on Phase 1's processes and services. Performance items from Phase 12 may be pulled forward when a phase leaves slack.

- Security fix (between 8.8 and 8.9): user pointers validated inside copy_user/copy_str_user;
  mmap/chan_create/chan_recv error paths fixed; uaccess boot self-test. Done.
- Security fix 2: wrap-safe ELF bounds, 64 MiB load cap with soft OOM, sys_wait/drv-recv/chan_recv
  error paths, pinned DMA vs munmap; ELF-bounds boot test. Done. (drv 403 returns an IOVA when VT-d translation is on; a host PA otherwise.)

- Bug fix (kexec stale TLB IPI): an intermittent O0 `os/kernel-bios` panic (#GP err=0x782 = IDT vector 0xF0 right after the IOAPIC came up, in the generation-1 kernel). A shootdown IPI that reaches a CPU while its interrupts are off is answered by `tlb_poll` but stays latched in the LAPIC IRR; the kexec CPU never re-enables interrupts, the handoff does not reset its LAPIC, and the successor installed the VEC_TLB gate only after its first `sti`. Fix: the gate is installed with the timer/PIT/spurious gates before the first `sti`; `on_tlb_ipi` counts stray IPIs. Made deterministic: `sys_kexec` latches one self-IPI on purpose after stop-machine, and every boot test requires `TLB IPI: 1 stale shootdown IPI(s) from the previous kernel handled before SMP` (without the fix it panics every time). Unsafe counts unchanged. Done.

### 9.0 carry-overs (done)
- UEFI OS-test load timeout raised 180s -> 360s (tests/os/run.sh).
- New ring-3 `examples/user/badptr.cud`: probes every pointer-taking syscall with 4 bad pointers (HHDM, kernel text, USER_TOP-straddling, USER_TOP); 56 probes, all EFAULT; verifies queued message survives failed recv and zombie survives failed wait. Found and fixed: `sys_chan_send` returned EINVAL for a bad buffer, now EFAULT.

## All-Cuditor tooling (porting Python tools to Cuditor; the "All-Forge rule" before the rename)

Directive: everything that can be Forge is Forge. One tool per commit, verified byte-identical against the Python original, then build/test scripts switch to the Forge build. Ported (Python kept as reference): tools/krel.py, tools/incudela-part.py, examples/efi/mkgpt.py, tools/ed25519.py (signing), tools/grammar_fuzz.py, tools/mkfont.py, tools/cudseal.py. Remaining Python: test helpers (tests/fld/pecheck.py, memimg.py, tests/lsp/client.py, tests/ed25519/gen.py and tests/os/boot.py ported to Forge). Runtime: selfhost/runtime.cud (runtime.s kept as reference).
- krel — *Status: done.* `tools/krel.cud` (`krel KERNEL.ELF OUT.s`). tests/krel/run.sh (in run_tests.sh) compares OUT.s, stdout and exit code with tools/krel.py on kernel and kernel-next (15 entries each), a synthetic high-half image with all three kinds, a low-only image (empty table) and an R_X86_64_32-to-high-half error image. tests/fld/run.sh now builds and uses krel.cud for its GNU-ld reference link. krel.py is kept only as the comparison reference.
- incudela-part — *Status: done.* `tools/incudela-part.cud` (`create DISK MIB --yes-add-incudela-partition` / `read DISK NAME`). Prerequisite commit: incudela-part.py takes `INCUDELA_GUID_SEED=N` (partition GUID bytes_le = pack('<QQ', N, 0)) so images are reproducible. tests/incudela-part/run.sh (19 checks, in run_tests.sh) compares the resulting image, stdout, stderr and exit code with incudela-part.py: create on 64/128 MiB mkgpt disks (16, 32, 1 MiB), no gap, missing flag, header/entry CRC corruption, no GPT, partition already exists, read of text/binary/empty/missing/deleted entries from a formatted partition, unformatted / no Incudela partition, usage. The unseeded Forge build writes a random RFC 4122 v4 GUID (getrandom) and differs only in the GUID and CRC fields. tests/os/forgefs.sh now builds and uses the Forge tool (not re-run under QEMU in this commit). Gaps: reads the whole image into memory (0.5 s on 64 MiB vs 0.02 s for the seeking Python version); the crc32 accumulator must be typed `int` (a dynamic-int accumulator hit a spurious "unsupported operand type(s) for ^" after ~8k iterations, compiler issue still open).
- mkgpt — *Status: done.* `examples/efi/mkgpt.cud` (`mkgpt out.img esp.fat [size_mib]`). Prerequisite commit: mkgpt.py takes `INCUDELA_GUID_SEED=N` (GUID k = pack('<QQ', N, k); partitions k = 0..2, disk 3). tests/mkgpt/run.sh (12 checks, in run_tests.sh) requires identical images: default 128 MiB, 64 and 40 MiB, ESP of 1 byte / empty / exactly 1 MiB / 1 MiB + 1 / 64 MiB on a 256 MiB disk, seeds 0 and 2^64-1, plus the does-not-fit failure; unseeded, the header and entry CRCs verify, primary and backup agree, and the four GUIDs are distinct RFC 4122 v4. examples/efi/build.sh builds and runs mkgpt.cud (EFI/OS boot suites not re-run in this commit). The u64 seed is parsed in 32-bit halves in both incudela-part.cud and mkgpt.cud (`int()` overflowed on 2^64-1); tests/incudela-part gained a seed-max case.
- ed25519 — *Status: done.* `tools/ed25519.cud` (`ed25519 public SEEDFILE`, `ed25519 sign SEEDFILE MSGFILE`, raw bytes on stdout) is a freestanding Linux program that includes examples/kernel/ed25519.cudi, so signing reuses the kernel verifier's SHA-512, field and group code. The only new crypto is `sc_muladd`, which computes (r + h·a) mod L. tests/ed25519-tool/run.sh (in run_tests.sh) requires byte-identical public keys and signatures to `tools/ed25519.py` on 26 vectors: RFC 8032 tests 1–2, seeds of 0–100 bytes, and messages crossing SHA-512 block boundaries and the 64 KiB read buffer (up to 200003 bytes). It also checks the RFC 8032 known answers, 5 usage errors (rc 2) and 2 missing-file errors (rc 1). Nothing invokes ed25519.py directly; cudseal.py imports it as a library and was left untouched here, so the seal build still signs with the Python code (until the cudseal port below). Hex verbs and a verifier (2026-11-23, item 6 batch 1): `hexpublic`, `hexsign` and `verify PUBHEX SIGHEX MSGFILE` (the kernel's `ed25519_verify`, at most 96 message bytes; exit 0/1, 2 on bad input), used by `cuditor pkg` for index signatures; tests/ed25519-tool adds 26 hex-vector checks, RFC 8032 test 1 verification, 8 round-trip lengths with a wrong-key rejection, another-message and changed-signature rejections, and 97-byte, bad-hex (5 forms) and missing-file errors, and the usage line lists the new verbs (4 more usage cases).
- grammar_fuzz — *Status: done.* `tools/grammar_fuzz.cud` (`--seed N --n COUNT`) reimplements Python's `random.Random` exactly: MT19937 seeded with init_by_array over the 32-bit words of abs(seed), randrange/choice by getrandbits rejection sampling, and random() as a 53-bit integer compared with exact thresholds ceil(p·2^53). It makes every draw in the Python generator's order, including list elements Python evaluates before `choice`. tests/grammar/run.sh now runs the Forge build (seed 1, n 160). tests/grammar-fuzz/run.sh (in run_tests.sh) requires the same stdout, exit code and generated build/fuzz tree as grammar_fuzz.py for seeds 1/160, 2/40, 3/40, 0, 2^40+7, −5 and 123456789/1, plus the defaults (seed 1, 200 programs); about 2 minutes. AST equality is textual: the `"file"` member and every `"l"` member are stripped instead of parsing the JSON. Compiler finding (fixed in the follow-up commit): two causes. (1) Hex literals on the bool/None band (2^62..2^62+3) or past int64 stayed raw, so `0x4000000000000000` was `True` and `^ 1` gave 1; untyped `&`/`|`/`^` had no bigint path and untyped `<<`/`>>` were raw machine shifts. (2) The ported tools' tests linked hosted binaries without `fld --base 0x100000000000`, so MT/CRC values aliased the data section and `__tag` read them as objects (the line-1677 TypeError). Now hex literals there lower to `__bigparse`, `__bitop` handles bigints (`__bigbit`, two's complement limbs) and boxes band results (`__ibox`), untyped shifts go through `__shift` (inline fast path for small non-negative ints), and every hosted tool test links at 2^44. tests/int_untyped_bitops.cud is the regression; the typed-local workarounds are gone.
- mkfont — *Status: done.* `tools/mkfont.cud` (`mkfont font.ttf out.cudi`) replaces PIL with a minimal TrueType stack in integer arithmetic: sfnt/head/hhea/OS2/hmtx/maxp/cmap(4)/loca/glyf parsing (simple glyphs, quadratic outlines), a bytecode interpreter reproducing FreeType 2.14 hinting in v40 backward-compatibility mode (fpgm/prep/CVT scaling, phantom points, MulFix/MulDiv rounding, SHPIX/DELTAP y-only, IUP), and the ftgrays smooth rasterizer (DDA conics, cell cover/area). A pixel is set at coverage ≥ 110, as in mkfont.py. The output is byte-identical: examples/kernel/font.cudi and the 'F'/'g' preview. tests/mkfont/run.sh (in run_tests.sh) checks it against the committed font.cudi and, when PIL is installed, against live mkfont.py runs on DejaVu Sans Mono, Mono-Bold, Mono-Oblique and Sans-Bold. Gaps: only the opcodes these fonts use are implemented; other fonts (DejaVu Serif, Liberation, …) exit 1 with `unsupported TrueType opcode N` rather than give a different font. No composite glyphs or other sizes. No build script ran mkfont.py, since font.cudi is committed, so nothing needed switching; mkfont.py is kept as the reference.
- read_file fix — *Status: done.* `read_file` returned a raw 0 when the open failed. That value was neither None nor an object, so `is None` was False and `len`/indexing segfaulted. rt_read_file now returns None. The compiler's own input/include checks use `is None` (reseeded; FIXPOINT/SEED OK). Regression: tests/read_file_missing.cud. Every ported tool now exits 1 with `<tool>: cannot read PATH` on a missing input: krel, incudela-part create/read, mkgpt, mkfont, and ed25519 (which has its own syscalls and already did). grammar_fuzz takes no input file. The mkfont `__tag` guard is gone. The Rust bootstrap's runtime (src/main.rs, optional cross-check only) still returns 0.
- cudseal — *Status: done.* `tools/cudseal.cud` (built as `build/cudseal`) is a freestanding Linux program that seals exactly like `tools/cudseal.py`: Seal v3 by default (384 bytes, every slot signs trailer[0:64] ‖ SHA-256(trailer[64:144])), `--v2` (160 bytes), `--extra-key` (second slot; an empty key file adds none, as in Python), `--alg-id`, `--proof-byte`, `--module`, `--foreign` (EI_OSABI 3 only, level 3) and `--pub`. It runs `build/cudc SRC /dev/null --unsafe-report` in SRC's directory (fork/chdir/execve, stdout and stderr captured in memfds), reproduces the count/own-ops regexes, the `relpath` baseline lookup and the greedy `caps(...)` match by hand, and streams the image (SHA-256, then O_APPEND of the trailer). The repo root comes from /proc/self/exe. Signing reuses ed25519.cud's code, now in `tools/ed25519sign.cudi`; SHA-256 is the kernel seal verifier's (`tools/sha256.cudi`). tests/cudseal/run.sh (in run_tests.sh) compares the sealed image, stdout, stderr and rc with Python in 33 cases: every option and combination the build uses, caps parsing, --pub seeds of 0/1/32/100 bytes, and all of Python's error messages. Unreadable inputs: Python dies with a traceback, Forge prints `cudseal: PATH: cannot read ...`; both exit 1. Switched (verified without QEMU): examples/user/build.sh and examples/modules/build.sh, whose full output trees (every .elf/.ko, seal.pub) were byte-identical to a Python-sealed build; and tools/busybox/build.sh, whose --foreign seal of the real BusyBox image matched Python byte for byte. Not run: the QEMU boot tests that load these images (tests/os). cudseal.py is kept as the reference.
- runtime.s — *Status: done (first script-free step of the item-9 remainder).* `selfhost/runtime.cud` (`# cuditor: no-runtime`) is the hosted runtime as 150+ `@naked` Forge functions whose bodies are the original instructions as inline asm (fallthrough between functions is kept: cudc emits naked functions back to back in source order; the alias label `rt_saveall` ends the previous function; the .data/.bss tail rides in the last function so symbol order is unchanged). build.sh compiles it with the seed (`build/runtime.s`) and embeds that instead of the hand-written file. Byte-identity: fas assembles both to identical .text/.data/.bss/.rela/.symtab/.strtab bytes, and hosted programs (tests/closures, tests/gc, tools/fmt) linked from either compiler are byte-identical binaries; the embedded text differs only in comments, indentation and the section directives cudc adds, so the compiler was reseeded (FIXPOINT/SEED OK). tests/rtport/run.sh (in run_tests.sh) checks the normalized assembly equals selfhost/runtime.s and build/runtime.s is current. selfhost/runtime.s is kept as the reference. Next in the item-9 remainder: build/test shell scripts and Python test helpers, one per commit.
- pecheck — *Status: done.* `tests/fld/pecheck.cud` is the PE32+ structure check (MZ/PE signatures, machine 0x8664, PE32+ magic, EFI application subsystem, image base 0x10000000, section/file alignment, NX_COMPAT, no W+X section, every section aligned and inside SizeOfImage, entry in an executable section). tests/fld/run.sh now builds and runs it for `fld/pe-structure`. tests/pecheck/run.sh (in run_tests.sh) requires the same stdout and exit code as tests/fld/pecheck.py on the real fld loader image and on six one-byte corruptions (MZ, PE signature, machine, subsystem, NX_COMPAT, section alignment), plus a missing-input check. On a failed check Python exits 1 with an AssertionError traceback and Forge with a one-line `pecheck: ...` message, so only stdout and rc are compared. pecheck.py is kept as the reference.
- memimg — *Status: done.* `tests/fld/memimg.cud` compares two executables' loaded images (PT_LOAD vaddr, size, flags, contents with .bss zero-fill, and the entry point) and prints exactly what tests/fld/memimg.py prints (`SAME`/`DIFF` line, `SEGS differ [...]` with Python tuple reprs, `bytes differ at 0x...`). 64-bit addresses are kept as 16-digit hex strings (unsigned order is string order), since inferred-int arithmetic raises OverflowError past 2^63 and the kernel's high half is 0xffffffff8.... tests/fld/run.sh and tests/dwarf/run.sh (dwarf/image-unchanged-by-g, same semantics as before: the output is discarded; inv234 found that this made the check vacuous, and the test now requires the `SAME` line) now use it. tests/memimg/run.sh (in run_tests.sh) requires identical stdout and rc to the Python on identical/different hosted tools (both orders), a flipped byte, a changed entry, a larger .bss, the two kernels, a flipped byte in a high-half kernel segment, plus a missing-input check. memimg.py is kept as the reference.
- hosted os library: directories and processes — *Status: done.* Prerequisite for the shell-script and test-helper ports. selfhost/prelude.cud adds Python-named calls over raw syscalls: `os.listdir` (open O_DIRECTORY + getdents64, kernel order, no `.`/`..`), `os.path.isdir`/`isfile`, `os.mkdir`, `os.chmod`, `os.chdir`, `os.getpid`, `os.fork` (flushes stdout first), `os.execv` (searches $PATH when the name has no `/`, passes the current environment), `os.waitpid` (returns `[pid, status]`), `os.waitstatus_to_exitcode`, `os.pipe` (O_CLOEXEC), `os.dup2`, `os.read`, `os.write`, `os.close`, `os._exit`; errors raise FileNotFoundError/OSError. Forge extension: `os.run(argv, cwd=None, merge=False, timeout=0)` returns `[exit code, stdout, stderr]` (stdin /dev/null; -N for a signal; 127 if exec fails; timeout=N seconds arms alarm(N) in the child, which survives execve, and reports 124 like timeout(1); drains stdout then stderr, so a child writing >64 KiB of stderr before closing stdout needs merge=True). The seed was refreshed (the prelude is embedded in the compiler). tests/oslib/run.sh (in run_tests.sh, honours CUDC_FLAGS) runs 21 checks: listdir (sorted, empty, 300 entries over several getdents batches, missing, not-a-dir), isdir/isfile, run (stdout, stderr+rc, merge, cwd, 200 KB output, timeout hit and not hit, missing program, signal), fork+execv+pipe+dup2+waitpid, pipe read/write/EOF, chmod +x then run, chdir, getpid.
- pkg sha256 fix — *Status: done.* `cuditor pkg sha256` of an empty file raised `TypeError: unsupported operand type(s) for &`: the untyped `rotr` built `x << (32 - n)` (up to 2^63) as a raw dynamic int, and a value inside the GC heap's reserved range (0x200000000000 + 64 GiB, below the heap top) is read as a heap object by the tag check (here a 0x200000002000 became a list). rotr is now typed `int`, so the intermediate never reaches the dynamic tag check; hashes are unchanged. The failure had been hidden by a stale build/pkg; it showed once build/pkg was rebuilt. Regression: tests/pkg `sha256-matches-sha256sum` (empty file). Known gap: any untyped int in that address range is still misread; typed `int` code is unaffected.
- fas/fld missing input — *Status: done.* `build/fas` crashed with a segfault diagnostic and `build/fld` with `value cannot be sliced` when an input file was missing. Both now print `fas: cannot read PATH` / `fld: cannot read PATH` on stderr, exit 1 and write no output (fld checks every object, including after a good one). Tests: `fas missing-input` in tests/fas/run.sh; `fld missing-input` and `fld missing-second-input` in tests/fld/run.sh. Reseeded (seed fas/fld; SEED TOOLS OK).
- fmt_files.sh → `fmt --list` — *Status: done.* tools/fmt.cud `--list` walks the repo with `os.listdir` (same roots, exclusions and byte-order sort as tools/fmt_files.sh) and prints the CI file set; `cuditor fmt` with no files and tests/fmt/run.sh use it. tools/fmt_files.sh stays as the reference: tests/fmt/run.sh adds `fmt-list-matches-sh`, which requires the two lists to be identical.
- reseed.sh → reseed.cud — *Status: done.* tools/reseed.cud (`./cuditor reseed`, built to build/reseed) finds the repo from argv[0], compares build/stage2.s and build/stage4.s itself with cmp(1)'s exact messages (`differ: byte N, line L` on stdout; `EOF on F after byte N, line L` / `in line L` on stderr; exit 1), copies build/cudc, fas and fld to seed/ with mode 755 (`os.chmod`), and writes seed.sha256 from a built-in byte-wise SHA-256; a missing input exits 1 with `reseed: cannot read P`. tools/reseed.sh stays as the reference: tests/reseed/run.sh (in run_tests.sh, 7 checks) runs both in scratch repo skeletons for green, byte-diff, both prefix forms and a long file and requires identical stdout, stderr, exit code and seed/ bytes and modes, plus the SHA-256 against sha256sum and the missing-input error.
- cud_test.sh → cud_test.cud — *Status: done.* tools/cud_test.cud (`./cuditor test`, built to build/cud_test on demand) builds each file with `cudc --test` plus $CUDC_FLAGS in build/cud_test.tmp, runs every test block in its own process via `os.run(..., timeout=10)` from the file's directory, and prints the same JSON report (exit 124 → `"timeout"`; a test killed by signal N reports 128+N like the shell did). tools/cud_test.sh stays as the reference: tests/testblocks/run.sh adds 4 `forge-test-matches-sh-*` checks (default set, a failing test, a build failure, a 10 s timeout) requiring identical JSON with the `ms` timings zeroed and the same exit code. `cuditor verify` still runs the shell version until the next item.
- cud_verify.sh → cud_verify.cud — *Status: done.* tools/cud_verify.cud (`./cuditor verify`, built to build/cud_verify; the driver also builds build/fmt and build/cud_test) runs the same parse / fmt / build / test / optional unsafe checks per file and prints the same JSON report. One deliberate difference: fas/fld stdout is discarded, where the shell let it leak into the JSON stream (the build check fails either way). tools/cud_verify.sh stays as the reference: tests/testblocks/run.sh adds 5 `forge-verify-matches-sh-*` checks (default set, fmt failure, parse failure, a failing test block, `--unsafe-report` on a user program) requiring identical JSON and exit code.
- tests/lsp/client.py → client.cud — *Status: done.* tests/lsp/client.cud drives `cuditor lsp` over two pipes (`os.fork`/`os.pipe`/`os.dup2`/`os.execv`) with Content-Length framing and the JSON reader/writer from tools/lsp.cud, on a scratch copy of tests/lsp/proj, and runs the same 45 checks in the same order with the same PASS/FAIL names (dict equality is structural, positions are UTF-16 code units). tests/lsp/run.sh builds and runs it under `timeout 300` (the client has no per-message timeout); `FORGE_LSP_PY=1` also runs client.py, kept as the reference, and requires the same output.
- tests/ed25519/gen.py → gen.cud — *Status: done.* tests/ed25519/gen.cud builds the same 12 vectors (6 keys and message sizes, plus flipped R/S/message, non-canonical S + L, the wrong key and a non-point key), signing with a build of tools/ed25519.cud through `os.run`, and writes the verifier test program. tests/ed25519/run.sh requires it to equal the committed edtest.cud byte for byte, then builds and runs it. gen.py stays as the independent cross-check (its signatures come from `cryptography`, not from our signer) and runs with `FORGE_ED25519_PY=1`. The generator splits the `no-runtime` pragma string it emits so the tool itself is not compiled freestanding. The fixture tests/ed25519/edtest.cud itself was listed in .gitignore, so fresh clones lacked it and ed25519/gen-matches-committed failed there; it is now tracked (the generator is deterministic and both gen.cud and gen.py reproduce it byte for byte).
- lexer heap-range literal fix — *Status: done.* `print(8192 | 35184372088832)` failed to compile with `error: line 600: unsupported operand type(s) for -`: the lexer built decimal literals in an untyped `v`, and the partial value 35184372088880 (0x200000000000 + 48, the GC heap base plus 48) is 8-aligned inside the compiler's own heap range, so the next `- 48` read it as a heap object. The decimal accumulator is now a typed `dv: int`; the >19-digit / wrap / bool-None-band check that routes a literal to `__bigparse` tests `dv` (the band as `dv >> 2 == 2**60`: an untyped band value reads as True/False/None, and a typed band literal folds to `False`). Reseeded. Regression: tests/heap_range_literal.cud. Remaining gap (same root cause as the untyped-int item): a literal whose *final* value is an aligned address inside the compiler's live heap (e.g. 35184372088880) is still stored untyped in the token and misread during codegen, as are hex literals, whose accumulator stays untyped because it relies on bigint promotion past int64.
- untyped ints in the GC heap range — *Status: known limitation (documented, not fixed).* Dynamic (untyped) ints are raw 64-bit words, and the tag check (`rt_tag_r`, likewise `rt_gc_mark`) treats any 8-aligned value v with rt_hlo < v < rt_hp (heap at 0x200000000000, 64 GiB reserve) — or inside the data section for binaries not linked at `fld --base 0x100000000000` — as an object and reads its tag at -1(v). An untyped int that lands there is misread (TypeError, wrong output such as `[]`, or a crash). There is no safe local fix: an int equal to a live object's address is bit-identical to that pointer, so stricter checks (page table + slot alignment, a non-round heap base) only make collisions rarer and add work to the hot tag path; routing such literals through `__bigparse` does not help because the result is a raw int again. Typed `int` code is unaffected; the workaround is to type locals, parameters and returns that can hold such values (as done for pkg `rotr` and the lexer). The compiler still misreads a literal whose final value is an aligned address in its own live heap (e.g. 35184372088880), and hex literals in that range.
- (possible future item, not approved) heap-range int boxing — box untyped ints that fall in the heap/data ranges the way bool/None-band values are boxed (`__ibox`): a range check in every untyped arithmetic fast path, in `__bigmk` normalisation and at every typed→untyped conversion (which the band boxing also misses today). Large compiler/prelude change with a measurable cost on untyped arithmetic; needs a design and benchmark first.
- os poll/FIFO prerequisite (for the boot.py port) — *Status: done.* The prelude os library gains `os.mkfifo(p, mode=0o666)` (mknod with S_IFIFO, for QEMU `-chardev pipe` FIFOs), `os.open(p, flags, mode=0o666)` (raw Linux flags, O_CLOEXEC added; 2048 = O_NONBLOCK), `os.set_blocking(fd, flag)` (fcntl O_NONBLOCK; a read with no data then raises OSError errno 11) and `os.poll([[fd, events], ...], timeout_ms=-1)`, which returns `[fd, revents]` for the ready entries in input order (`[]` on timeout, EINTR retried). tests/oslib adds 7 checks (poll timeout/readable+writable/HUP, set_blocking EAGAIN, mkfifo, FIFO write → poll → read, open of a missing file → FileNotFoundError). Manual reseed (prelude change: stage3 == stage4, seed binaries and seed.sha256 replaced). Note `os.path.isfile` is true for any non-directory, including FIFOs.
- tests/os/boot.py → boot.cud — *Status: done.* tests/os/run.sh builds tests/os/boot.cud to build/os/boot (cudc/fas/fld, base 0x100000000000) and runs it for the four QEMU boot paths (kernel-bios, kernel-bios-smp1, kernel-uefi, efi-loader-gpt); boot.py is kept as the reference. Same arguments and PASS/FAIL/HANG/SLOW output, serial markers, stack_dump symbolization, screendump PPM + font OCR of the framebuffer, SCRIPT/KEYS input and the retry/stall logic (FORGE_BOOT_NO_RETRY, FORGE_BOOT_STALL). QEMU runs via os.fork/os.dup2/os.execv with serial on pipes read through os.poll; the HMP monitor is a `-chardev pipe` on two os.mkfifo FIFOs instead of a Unix socket. Validated with one QEMU-only run of tests/os/run.sh: all four boot paths PASS with the framebuffer rows decoded, plus the remaining os checks.
- examples/modules/build.sh → build.cud — *Status: done.* examples/modules/build.cud (built to build/modules-build by examples/kernel/build.sh, which now runs it) builds the seven test modules with cudc/fas (plus $CUDC_FLAGS) through `os.run`, rebuilds and uses build/cudseal (`--module`, build/user/seal.key), and writes the .raw copies and the negatives (unsealed, tty1u, tampered = byte 0x50 flipped in Forge instead of a python3 one-liner, userimg). It finds the repo from argv[0], runs from examples/modules like the script, takes an optional OUTDIR, and stops at the first failing step with its exit code (sh -e). `cp` is reproduced including mode: an executable source (access X_OK) gives 0755. examples/modules/build.sh is kept as the reference: tests/modules-build/run.sh (in run_tests.sh) requires the same stdout, stderr, exit code and all 25 artifacts byte- and mode-identical, at default flags and at -O0, then restores the suite's own build/modules.
- examples/user/build.sh → build.cud — *Status: done.* examples/user/build.cud builds and seals the 20 user programs (cat with the second key), the seal v3/v2 and 6.3/6.4 negatives (v2, alg-id, proof-byte, unsealed, tampered, forged, linuxabi) and the EI_OSABI=3 Linux-ABI test programs, doing the python3 byte patches in Forge; keys are made from /dev/urandom only when missing; BusyBox still goes through tools/busybox/build.sh when $BB_SRC has the tarball. examples/kernel/build.sh runs it (build/user-build). tests/user-build/run.sh checks identical stdout, stderr, exit code and artifact bytes and modes (110 files) against build.sh at default flags and -O0, the BusyBox branch (a fake tarball fails the SHA-256 pin with rc 3 in both), and fresh 32-byte key generation. build.sh is kept as the reference.
- tools/busybox/build.sh → build.cud — *Status: done.* tools/busybox/build.cud pins the tarballs (SHA-256 via sha256sum, upstream signatures via gpg when $BB_SRC/gnupg exists), builds GNU make and musl from source when missing, extracts BusyBox with tar -xjf (dropping the python3 tarfile one-liner), builds it with musl-gcc, sets EI_OSABI = 3 in Forge and seals it --foreign. examples/user/build.cud runs it (build/busybox-build). tests/busybox-build/run.sh checks identical stdout, stderr, exit code and busybox.elf bytes and mode against build.sh (SOURCE_DATE_EPOCH fixed for both) for a cold build, a warm one, and the refusals: tarball missing (rc 2), pin mismatch (rc 3), bad signature (rc 4). build.sh is kept as the reference. tools/busybox/bzip2 (the Python bz2 shim) is ported separately (entry below).
- tools/busybox/bzip2 → bzip2.cud — *Status: done.* tools/busybox/bzip2.cud (built to build/bzip2; tools/busybox/build.cud puts it on the BusyBox build PATH for `tar -xjf`) is a Cuditor port of libbzip2 1.0.8 matching Python's bz2: compress at level 9 (workFactor 30) and `bzip2 -d` decompress (concatenated streams, trailing garbage after a good stream ignored). Errors exit 1 with Python's last traceback line on stderr. tests/bzip2/run.sh (in run_tests.sh) requires identical stdout, exit code and last stderr line against the Python shim on empty/tiny/RLE/periodic/random/1 MB+ inputs, concatenated/truncated/corrupt streams, and the BusyBox tarball when present. tools/busybox/bzip2 is kept as the reference.
- examples/efi/build.sh → build.cud — *Status: done.* examples/efi/build.cud (built to build/efi-build; run_tests.sh and tests/os/run.sh now run it) builds the UEFI loader (cudc/fas, fld --format pe), runs the kernel build, makes the FAT32 ESP with mtools (loader, kernels, init, bin/, mod/, docs/ with the LFN notes file, big.bin and hello.sh, apps/ manifests; empty Microsoft/debian vendor dirs; BOOT\BOOTX64.EFI as this test disk's removable-media fallback) and the GPT disk with build/efi/mkgpt. The script's printf and python3 big.bin one-liner are done in Forge; ESP contents unchanged, so the loader still writes only under \EFI\Incudela\. tests/efi-build/run.sh (in run_tests.sh): default, O0 and a missing-input case (scripts/hello.sh hidden: same mcopy error and exit code, same partial build/efi) need identical stdout, stderr, exit code and artifact bytes and modes, with SOURCE_DATE_EPOCH and INCUDELA_GUID_SEED fixed, including byte-identical esp.fat and disk.img (tools/repro-mformat pins the FAT volume serial to the low 32 bits of the epoch; INCUDELA_GUID_SEED already pins the GPT GUIDs). efi-build/esp-reproducible builds the script twice and requires matching sha256 of those two images. A mutation of the big.bin pattern was caught. examples/efi/build.sh is kept as the reference.
- examples/kernel/build.sh → build.cud — *Status: done.* examples/kernel/build.cud (built to build/kernel-build; run_tests.sh and tests/os/run.sh now run it; examples/efi/build.cud builds it) builds the user programs (build/user-build) and BusyBox (build/busybox-build), the test modules (build/modules-build), the multiboot2 kernel (cudc/fas, fld --format kernel with image KASLR), a second kernel with another version string for the kexec test (kernel-next.elf; the script's sed/grep/cmp are done in Forge; the two ELFs must differ) and a BIOS+UEFI hybrid GRUB ISO (tools/repro-mkrescue, a wrapper around grub-mkrescue). With SOURCE_DATE_EPOCH set, the ISO is byte-reproducible: the wrapper replaces grub-mkrescue's wall-clock UUID (this grub-mkrescue 2.12 does not honour SOURCE_DATE_EPOCH) with the epoch's `YYYY-MM-DD-HH-MM-SS-00` in the extracted tree, remakes the El Torito efi.img with the pinned FAT serial, and rebuilds through tools/repro-xorriso so --modification-date and --set_all_file_dates pin volume and file timestamps. tests/kernel-build/run.sh (in run_tests.sh): default, O0 and a missing-input case (grub.cfg hidden: same cp error and exit code, same partial build/kernel) need identical stdout, stderr, exit code and artifact bytes and modes, including forge.iso; kernel-build/iso-reproducible runs the wrapper twice on the same iso/ tree and requires matching sha256, also against the script's ISO. examples/kernel/build.sh is kept as the reference. Cleanup (0.15.1): tests/kernel-build/run.sh chmods the xorriso extract tree (`$T/x`) before `rm -rf` (isot and the EXIT trap), so the read-only extract no longer floods stderr with Permission denied.
- read_file on unseekable files (boot-harness HANG fix) — *Status: done.* inv78 hung in the Forge boot harness, not the guest: after a 60 s serial stall on efi-loader-gpt, its HANG path called `read_file("/proc/loadavg")`. `rt_read_file` sized the string from `lseek(fd, 0, SEEK_END)` without checking it; seq_files (and pipes) fail with -EINVAL/-ESPIPE, so a negative length reached the allocator as size class 0 and `rt_refill`'s free-list carve looped forever (stride 0). Fix: `rt_read_file` closes the fd and returns None when lseek fails (documented as "None on failure"; same change in the reference selfhost/runtime.s so rtport-asm-identical holds); boot.cud reads /proc/loadavg with os.open/os.read (`proc_text`) so the HANG dump still shows the load. Regression tests/read_file_unseekable.cud (/proc file and a FIFO → None; os.read of /proc works). Manual two-pass reseed (runtime change). Dump material in /workspace/hang-dumps/inv78. Open question (closed, plan v1.8 item 6): why the efi-loader-gpt boot stalled 60 s after KERNEL OK — see the item below.
- efi-loader-gpt 60 s post-KERNEL-OK stall — *Status: done (plan v1.8 item 6).* Intermittent HANG after `KERNEL OK` (inv78): the kernel waited up to 5 s (500 LAPIC ticks) for the harness to send `q` on COM1 so it could screendump, then called `qemu_exit`. The wait loop used `hlt()`. COM1 is polled (`serial_poll` reads the LSR; no RX interrupt), so the only wakeup was a LAPIC timer IRQ. After kexec the timer is sometimes not firing, so `hlt()` slept through the `q` (already in the UART) until the harness's 60 s `FORGE_BOOT_STALL`. Not a firmware boot-order timeout (OVMF reaches the loader in ~1.6 s; Boot0001 "UEFI Misc Device" is the virtio data disk with `BOOTX64.EFI` removed, a fast Not Found) and not a raised test timeout. Fix: re-arm the LAPIC timer, bound the wait with the TSC (`tsc_per_ms * 5000`) and `cpu_relax()` instead of `hlt()`, and print `debug-exit N ms after KERNEL OK`. `os/efi-loader-gpt-post-ok` requires N < 8000 (before: a hung boot sat silent for 60 s; after: N is the screenshot-to-`q` latency, typically ~1 s). ESP writes remain only under `\EFI\Incudela\`. Unsafe baseline unchanged.
- serial_putc THRE wait bound (os/kernel-bios-smp1 hang) — *Status: done.* inv118b O2: first `os/kernel-bios-smp1` boot hung 411 s after kexec; vCPU RIP was `serial_putc` (`inb(COM1+5)` / THRE), mid `seal_test`/`fs_read_file` of a sealed image, IF=1 HLT=0, `RDI='u'`. The wait was unbounded `cpu_relax()`. A backed-up QEMU stdio pipe leaves THRE clear, so the kernel spun until the harness 2× timeout. Fix: TSC-bound the wait (10 ms once `tsc_per_ms` is calibrated; a spin cap before that), `serial_init` once and retry, then drop the character. `inb`/`outb` count in `serial_putc` is still 2; live unsafe report remains 170 / 0 / 709 / 7. The harness drain/stall-check fix is a separate commit. The test is not quarantined.
- boot harness drain-before-HMP and per-iteration stall check — *Status: done.* Companion to the `serial_putc` bound: `tests/os/boot.cud` (and the `boot.py` reference) now drain QEMU stdio every loop iteration and once more immediately before any HMP command on the hang path, then apply `FORGE_BOOT_STALL` (still 60 s, not raised) every iteration rather than only when the test deadline fires. A `--self-test` mode checks the stall predicate and a pipe drain with no QEMU (`os/boot-harness-self-test`; expected-results is 35 names). smp1 markers are unchanged; the test is not quarantined.
- boot harness settled screendump (inv128 O0 os/efi-loader-gpt FAIL) — *Status: done.* inv128 O0 failed once with framebuffer row 46 = `KERNEL OK` followed by spaces and `ck == front` (the tail of the row above). Cause: `putc` writes each character to serial before the framebuffer, and the newline after `KERNEL OK` scrolls the console, which redraws changed cells left to right; the harness started the screendump as soon as `KERNEL OK` was on serial, so a dump could land mid-redraw (the window is wider at -O0). Not reproduced in 12 isolated O0 boots (6 on the batch, 6 on its base), and the fresh gate inv128b passed. Fix (harness only, `tests/os/boot.cud`): wait for `KERNEL OK\n`, then dump until two consecutive dumps decode identically (at most 4, about 3.5 s, inside the kernel's 5 s wait for `q`) and check that settled screen. A real rendering bug still fails because its wrong text is stable. `--self-test` adds `boot-harness rows-stable`. The kernel and the expected text are unchanged; `boot.py` stays the original reference (it is no longer run).

- reproducible ESP volume serial and ISO UUID — *Status: done (plan v1.8 item 7).* Two clean builds with `SOURCE_DATE_EPOCH` (and `INCUDELA_GUID_SEED` for the GPT disk) now give byte-identical `esp.fat` / `disk.img` and `forge.iso`. The FAT volume serial is no longer left to mformat's RNG: `tools/repro-mformat` passes `-N` with the low 32 bits of the epoch (used for the Forge ESP and, on PATH, for grub-mkrescue's El Torito `efi.img`). grub-mkrescue was still stamping a wall-clock UUID into `.disk/<date>.uuid`, the GRUB core images, and `--modification-date=` (it does not read `SOURCE_DATE_EPOCH`); `tools/repro-mkrescue` runs grub-mkrescue, then replaces that same-length UUID in the extracted tree with the epoch's `YYYY-MM-DD-HH-MM-SS-00`, remakes the El Torito FAT via `tools/repro-mformat`, and rebuilds the ISO with `tools/repro-xorriso` (`--modification-date` and `--set_all_file_dates`). Tests: `efi-build/esp-reproducible` builds the EFI script twice and compares sha256 of `esp.fat` and `disk.img`; `kernel-build/iso-reproducible` runs the wrapper twice on the same `iso/` tree and compares sha256 of `forge.iso` (also against the script build). Script vs Forge artifacts must match in full, including those images. *Fix (2026-11-13, inv149 O0):* the second esp-reproducible build inherited the gate's `CUDC_FLAGS=-O0` while the first ran with `CUDC_FLAGS=""`; once -O0 became real in freestanding code the two ESPs held different kernels, loaders and user programs (kernel.elf 654,520 vs 675,000 bytes) and the FSInfo and FAT bytes differed. The second build now pins the same empty CUDC_FLAGS. ESP layout is unchanged (writes only under `\EFI\Incudela\`, plus the existing test-disk `\EFI\BOOT\BOOTX64.EFI` fallback). Unsafe baseline unchanged. *Fix (inv235, found by public CI):* on Ubuntu 24.04 (mtools 4.0.43) two clean builds gave different `esp.fat` / `disk.img` and `forge.iso`, failing efi-build default, O0, missing-input and esp-reproducible and kernel-build default, O0 and iso-reproducible. Cause: `mformat -C` sizes the new image by writing its last sector, and before mtools 4.0.48 ("uninitialized buffer fix in mformat") that sector came from an uninitialized buffer (reproduced with 4.0.43 built from source outside the repo: two `mformat -C` images differ only in the last sector). `tools/repro-mformat` now zeroes that sector after `-C`, which is what 4.0.48 writes, so box images are byte-identical to before. New check efi-build/mformat-last-sector (a shim mformat that fills the sector with 0xa5; fails on the old helper). With 4.0.43 efi-build passes 4/4; 4.0.43 and 4.0.48 images still differ in the boot sector's OEM name (`MTOO4043` / `MTOO4048`), which the tests never compare across machines. The inv235 gate also found the OS boot harness gluing its box-freeze notes to the next guest serial line (`os/kaslr` counted 4 of 5 kexecs); fixed in `16f9c5d` with self-test check `boot-harness note-own-line`.
- unsafe baseline ratchet (kernel ops 716 → 709) — *Status: done.* `tests/unsafe/baseline.txt` is a ceiling (`counts may shrink, never grow`; tests/unsafe/run.sh compares with `-le`). The kernel line was still 170 / 0 / 716 / 7 from 022c21a, while the live `cudc --unsafe-report` on `examples/kernel/kernel.cud` is 170 functions, 0 blocks, 709 ops, 7 top-level asm blocks (it shrank through later work, including the post-KERNEL-OK wait change). The ops ceiling is ratcheted down to 709 so a regression cannot hide under the old 716 cap. Functions, blocks and top-level asm were already at the live counts and are unchanged. README records the new ceiling.
- README kernel unsafe ceiling line — *Status: fixed (2026-11-15 assessment).* README said the ceiling in `tests/unsafe/baseline.txt` is 170 functions / 709 ops; the baseline was lowered by Stages 3e and 3f to 168 / 0 / 659 / 7, which is what `cudc --unsafe-report` on `examples/kernel/kernel.cud` reports at 7c0bbc4. README now gives 168 / 659. (The assessment's first version of this commit ratcheted 709 to 708 on 1a51b4b; 3e and 3f superseded it.)
- unsafe test result names carry the directory — *Status: done (2026-11-15 assessment).* tests/unsafe/run.sh printed `unsafe-baseline-$f` and `unsafe-prov-$f`, so examples/user/hello.cud and examples/modules/hello.cud gave two results with the same name and a failure in one could be read as the other. The names are now `unsafe-baseline-<dir>/<file>` and `unsafe-prov-<dir>/<file>` (`kernel/kernel.cud`, `user/hello.cud`, `modules/hello.cud`); the checks themselves are unchanged (85 results, all distinct).
- run_tests.sh fails closed on the OS tests — *Status: done (2026-11-15 assessment; also raised by ChatGPT's 2026-11-15 review).* With the OS-test toolchain missing, `run_tests.sh` printed `SKIP tests/os` and could exit 0 without booting a kernel, so an ordinary run looked like a full pass. Now a missing qemu-system-x86_64 or grub-mkrescue is `FAIL tests/os` (exit 1); `SKIP_OS=1` is the only way to skip, and its line says the run is not a gate pass. The gate harness is unaffected (it reinstalls the tools first with tools/ostools.cud).
- docs/kernel-core.md Appendix A result count — *Status: done (2026-11-15 assessment).* It said `tests/os/expected-results.txt` has 35 entries; it has 39, and nine of them (boot-harness self-test, drivers-no-disk-write, the three bootpol boots, the three dwarf results and os/desktop) were named nowhere in the appendix. The count is corrected and a paragraph names them.
- Cuditor rename, language and tooling (rename commit 1 of 3, plus the ESP migration) — *Status: done (2026-11-16, Kyle approved the plan 2026-11-15).* Every `.forge` source is `.cud` and every `.fsi` include is `.cudi` (`git mv`, history follows); `forgec` is `cudc` (`build/cudc`, `seed/cudc-seed`), the driver `./forge` is `./cuditor` (a 3-line `./forge` shim stays for one release), `# forge:` pragmas are `# cuditor:`, `forge.toml`/`forge.lock` are `cuditor.toml`/`cuditor.lock`, `FORGEC_FLAGS` is `CUDC_FLAGS`, `FORGE_GUID_SEED` is `INCUDELA_GUID_SEED`, and forgeseal, forge-part, forge_test, forge_verify and c2forge are cudseal, incudela-part, cud_test, cud_verify and c2cud (docs/tools-*.md and tests/* follow). Compatibility for one release: the compiler reads both pragma spellings (`has_pragma`) and `import m` finds `m.cud`, then the old `m.forge`; pkg reads `forge.toml`/`forge.lock` when the new names are missing; the build scripts and run_tests.sh take `FORGEC_FLAGS` when `CUDC_FLAGS` is unset, mkgpt and incudela-part take `FORGE_GUID_SEED`. Reseeded in three passes (the compiler first learned both spellings and extensions under the old seed; the seed embeds the runtime assembly it generated, whose banner names the compiler, so the last pass makes the seed reproduce itself): FIXPOINT OK, SEED OK, SEED TOOLS OK. Internal symbols (`forge_alloc`, `forge_py_*`, `forge_bounds_fail`, the `forge_ast` JSON key, `forge/stats`) and the CHANGELOG history keep their names. tools/lsp.cud cut module names by the extension length (6), now 4.
- Incudela rename, OS strings and docs (rename commit 2 of 3) — *Status: done (2026-11-16).* The kernel version is `incudela-kernel 0.2.6` (kexec target `incudela-kernel 0.2.6-next`), the loader says `Incudela UEFI loader`, Forge FS is Incudela FS (format, magic `FORGEFS1` and partition type GUID unchanged), and the kernel, shell, desktop and user-program messages say Incudela; the boot command-line keys are `incudela.iommu=` and `incudela.desktop`, and the old `forge.iommu=`/`forge.desktop` are still read for one release (tests/os/desktop.sh boots with the old `forge.desktop` on purpose; bootpol uses the new key). tests/os/kexec-compat.sh still expects the 61b3e85 kernel to call itself `forge-kernel 0.2.6`. README opens with Incudela and Cuditor and a "Renamed from Forge" table (what changed, what is kept for one release, what is kept for good); BUILD_PLAN and GRAMMAR titles follow. Not renamed: the Linux personality's `uname` (nodename `forge`, release `0.2.6-forge`) and BusyBox's `forge-bb` config, since programs see them; the ESP folder moves in the migration commit.
- Licences (rename commit 3 of 3) — *Status: done (2026-11-16; Kyle chose Apache-2.0 for Incudela and MIT for Cuditor on 2026-11-15, copyright 2026 Kyle Curtis).* LICENSE says which applies where; LICENSE-APACHE and LICENSE-MIT hold the texts (and LICENSES/ for REUSE tools, with GPL-2.0-only for tools/busybox/busybox.config and a note for the upstream signing keys); REUSE.toml (REUSE spec 3.2) gives every path its SPDX identifier: the kernel, loader, user programs, modules, apps, the image tools (cudseal, incudela-part, krel, mkfont, mkgpt, ostools, repro-*, ed25519, busybox) and their tests are Apache-2.0, everything else is MIT. Cargo.toml: `cuditor-bootstrap`, `license = "MIT"`. Changed from the plan: no SPDX header line was inserted at the top of each source, because a new first line moves every line number that the goldens pin (tests/errors, typeerrors, diag, bounds traps, tools/optcov-allow.txt, DWARF line checks); REUSE.toml carries the same identifiers per path, and a header added to a file later wins. BusyBox (GPL-2.0) and CPython (PSF-2.0) are downloaded and verified, not vendored, and are covered by neither licence.
- old-to-new kexec test — *Status: done (2026-11-16).* Every kexec boot in tests/os/run.sh swaps two kernels built from the same tree, so a handoff-record change made on both sides (Stage 3f retyped both records) would agree with itself. tests/os/kexec-compat.sh extracts an older commit (`KXC_OLD`, default 61b3e85, the last before 3e/3f) with `git archive` into a temporary directory (no worktree, nothing in the repository changes), copies this tree's seal keys in so both kernels trust the same images, builds its compiler, kernel, ISO and ESP disk, checks SEED OK, no `fas:` errors, a different kernel.elf and the same seal.pub (`os/kexec-compat-build`). It then boots the old ISO with a test copy of the old ESP whose `\EFI\Incudela\kernel-next.elf` is this tree's, and requires the new kernel to adopt the old handoff (format v5, process-state records, the input driver record) and hand over once more (`os/kexec-old-to-new`, FORGE_BOOT_KEXEC=2). `KXC_BUILD_ONLY=1` stops after the build. tests/os/expected-results.txt: 39 -> 41.
- post-kexec prompt race (inv80/g67 kernel HANG fix) — *Status: done.* Both kernel-bios and kernel-uefi stalled after `kexec next` (last line "kexec: input service state carried: …"). Root cause: `kx_restore` made the adopted shell runnable before `kexec_resume` restarted the input service (two slow kbdd image reads) and printed its report; those kernel `puts` are not under `con_lock`, so they interleaved character-wise with the shell's prompt (`shk$e xec`, `commitss hs$o  far` in the dumps). The harness counts literal `sh$ ` prompts, never saw it, never sent the next line, and the guest waited forever (CPU0 in `proc_reap`'s yield loop, APs idle — not a scheduler/LAPIC bug; timer re-arm, EOI and irq_save balance checked). Fix: `kx_restore` calls `kexec_input_resume()` (kernel.cud) before any adopted thread becomes runnable; it sets `kb_svc = 1` first (input queues behind the carried journal entries, so they replay before any new tty input), seeds `kbd_shift`/`kbd_e0` from the carried decoder state, reads the images, starts kbdd and prints the report. Regression: boot.cud `FORGE_BOOT_KEXEC=N` repeats the handoff with serial and keyboard input sent the moment each new prompt appears; the post-kexec session keeps the test hooks so the shell can hand over again; run.sh's kernel-bios does 3 handoffs ("kexec: generation 3 kernel adopted", KASLR counts follow `KXR`). Reproduction: 6 single-kexec boots on old HEAD (idle and under host load) did not hang, but 4/6 logs showed kernel lines landing right after the post-kexec prompt (the window is real; it hangs only when the split falls inside `sh$ `). Fixed tree: 5/5 boots that reached the shell went through 3 handoffs with no interleaving. Dumps: /workspace/hang-dumps/inv80.
- FIXED (was KNOWN OPEN ISSUE): livepatch stop_machine/tlb_poll rendezvous deadlock — *Status: fixed.* Under host load the stop-machine initiator waited forever on `tlb_acks` while every other CPU sat parked in `tlb_poll` (IF=0). Root cause: `spin_lock` calls `tlb_poll` with interrupts on, so a timer tick inside the poll could reschedule the thread to another CPU (dumps show the timer firing inside `lapic_cpu()` in `tlb_poll`, then the TLB IPI nested inside that). The migrated thread answered and parked for the first CPU's request, and the stray answer was counted by the single shared ack counter against a later round, which finished early. Fix (examples/kernel/cpux.cudi): `tlb_poll` runs with interrupts held off and a per-CPU `tlb_in_poll` flag, so a nested entry leaves the request to the outer poll. The shared counter is replaced by per-round generations: the initiator bumps `tlb_gen` and posts it to `tlb_req_gen[c]`, each CPU answers by storing the round it served in `tlb_ack_gen[c]`, and the initiator waits until every `tlb_ack_gen[c] == tlb_gen`. The park loop keeps answering newly posted requests while it waits. The lapic timer handler was checked: it EOIs, then takes `rq_lock` and calls `schedule_l`, but a parked CPU has IF=0, so the handler never runs while parked. Regression: kernel self-test `stop_machine_stress` (kernel.cud), in which 3 threads hammer a contended spinlock with interrupts on while the test thread runs 3000 stop-machine rounds; marker `stop_machine stress OK: 3000 rounds` in tests/os/run.sh. Before the fix, 3 of 3 loaded boots hung in this test; after it, 5 of 5 pass. Dumps: /workspace/hang-dumps/kxfix6 and /workspace/hang-dumps/smx.
- cudseal caps after the Cuditor rename — *Status: fixed (inv165).* The rename turned every `# forge: caps(...)` line into `# cuditor: caps(...)`, but tools/cudseal.cud and the cudseal.py reference still matched only `forge:`, so every program was sealed with caps 0. tests/cudseal compared the two tools with each other, so it passed; every OS boot panicked at the kernel's `cat` seal self-test (`EFI/.../bin/catPANIC: : unexpected verification result`, 30 OS results in inv165). Both tools now read `cuditor:` and `forge:`, and tests/cudseal checks the resulting mask (`caps-spellings`).
- last old spellings after the Cuditor rename — *Status: fixed (2026-11-16).* tools/fsfuzz.cud still generated its programs with `# forge: no-runtime` and `# forge: stack-protector` (the old spelling, accepted only until 0.22.0 drops it), so fs-opt-fuzz and fs-opt-combos would stop testing the freestanding path then; they now write `# cuditor:`. The rename's text substitution also turned two compiler comments into nonsense: `has_pragma` said the old spelling was `# cuditor: p` and `load_mod` said the old module file was `dir/name.cud`; they name `# forge: p` and `dir/name.forge` again. And tools/pkg.cud's `read_lock` checked only for `cuditor.lock` and read it with `read_file`, so a project that still had only `forge.lock` failed `cuditor pkg build` with "no cuditor.lock" although README says `forge.lock` is read for one release; it now falls back to `forge.lock` like `cuditor.toml` does.
- deprecation warnings for the old spellings (0.21.1 rename cleanup) — *Status: done (2026-11-16).* Until now a `# forge:` program compiled silently to the same output, so nobody would notice before 0.22.0 removes the aliases. Each old spelling now prints one stderr line `warning: OLD is deprecated, use NEW (renamed 2026-11-16; the old name is removed in 0.22.0)` and still produces identical output: `# forge: P` pragmas and `import`ed `.forge` modules (cudc, once per spelling and compile; not in `--diag-json` mode, whose stderr is JSON lines), `forge: caps(...)` lines (cudseal.cud and the cudseal.py reference, once per source), `forge.toml`/`forge.lock` (`cuditor pkg`), `FORGEC_FLAGS` (./cuditor, run_tests.sh, and the build/test tools that read it directly), `FORGE_GUID_SEED` (mkgpt and incudela-part, both implementations, once per run) and `./forge`. tests/oldnames checks for each one that the old spelling warns exactly once, the new one is silent, the output (assembly, binary, disk image, lock or build) is byte-identical, and a control run without the setting differs, so an alias that was silently ignored cannot pass; tests/cudseal's caps-spellings case also requires the warning and an identical sealed image. The `forge.` boot command-line keys are not covered: the kernel reads them without a console warning.
- old-name aliases removed (0.22.0 cut, item 1) — *Status: done (2026-11-19).* As promised in README "Renamed from Forge", 0.22.0 stops reading every pre-rename spelling: `./forge` is deleted; cudc no longer reads `# forge:` pragmas (nor lists them in `--emit=ast-json`) or finds `.forge` modules; `./cuditor`, run_tests.sh, the build scripts, cud_test and cud_verify no longer fall back to `FORGEC_FLAGS`; mkgpt and incudela-part (Cuditor and Python) no longer read `FORGE_GUID_SEED`; `cuditor pkg` no longer reads `forge.toml`/`forge.lock`; cudseal (both) no longer reads `# forge: caps(...)`; the kernel no longer reads `forge.iommu=` or `forge.desktop` (os/desktop now boots with `incudela.desktop`). Kept: the `\EFI\Forge\` one-time migration path, the on-disk magics, the FS partition type GUID, `uname` strings, internal symbol names, `FORGE_REGISTRY` and the `forge.ap_delay=` test knob (never renamed). tests/oldnames now checks that each old spelling has no effect and prints nothing (all 12 checks fail on the 0.21 compiler and tools); tests/cudseal checks a `# forge: caps(fs)` copy seals caps 0. Kernel instructions 83,106 to 83,085 (the two key comparisons); unsafe report unchanged (168 functions, 659 ops).
- reseed for 0.22.0 (0.22.0 cut, item 2) — *Status: done (2026-11-19).* The checked-in seeds were last refreshed at 51f53b3 (step 4q); steps 4r to 4ak and the alias removal changed cudc, fas and fld since. `./cuditor reseed` after a FIXPOINT-green `./build.sh` on bc1a85f; the next `./build.sh` prints FIXPOINT OK, SEED OK, TOOLS OK and SEED TOOLS OK (before: two SEED NOTE lines). seed.sha256: cudc-seed 7928d08a…, fas-seed caec69e9…, fld-seed 76b48299….
- CHANGELOG 0.22.0 closed (0.22.0 cut, item 3) — *Status: done (2026-11-19).* The 0.22.0 heading carries the date and the alias removal and reseed entries; no git tag (CHANGELOG: the versions are groupings, there are no tags). Two record fixes: the step 4ae kernel count read 91,807 to 90,625, measured again at cc90ae0 and ad017f8 it is 91,805 to 90,623 (91,805 is also step 4ad's result); the Nov 17 step 4o row was in the schedule twice (the later copy is gone).
- CHANGELOG and titles after the rename — *Status: done (2026-11-16).* CHANGELOG.md is titled "Incudela and Cuditor changelog" and has entries for 0.20.1 (411b601, f334521), 0.21.0 (da81abc, 1aec031, 81c05dd, c01b041, 36252c3, f429c5a, 0b6ceeb) and 0.21.1 (the rename cleanup); older entries keep the names of their time. BUILD_PLAN's Phase 4 and All-Cuditor tooling headings follow the new names (README's title already did).
- tlb_test freed live workers — *Status: fixed (2026-11-16).* tlb_test waited for `tlbt_done == n` and then called `thread_free` on each worker, but a worker increments `tlbt_done` before it returns, so it can still be running. Under host load (a vCPU descheduled right after the increment) thread_free's check fired: `PANIC: thread_free: thread still alive`, right after the stack-canary line, in 61b3e85's kernel during an inv167 kexec-compat repeat with 6 busy host cores (the same code is in every later kernel). tlb_test now uses `thread_reap`, which waits for `T_DEAD`. New boot self-test `reap_test`: 4 pinned workers report and keep running until released; the parent must see all 4 still alive and reap them. With `thread_free` in its place the boot panics every time (`thread_free: thread still alive`, rc=35). tests/os/kexec-compat.sh applies the same one-line teardown fix to the archived 61b3e85 tree before building it (old build plus the 411b601 self-test teardown fix; the handoff format is untouched), since that kernel's boot self-tests run first and hit the same race.
- t3 and incudela-part after the Incudela rename — *Status: fixed (inv165).* The OS rename changed the greeting in tests/t3.cud to "Incudela" without updating tests/t3.expected (t3 and ast-pretty-semantic t3 failed), and changed the partition name in tools/incudela-part.py to "Incudela FS" while tools/incudela-part.cud still wrote "Forge FS", so the byte-for-byte py-vs-cud images differed (create-64-16, create-128-32, create-128-1, seed-max). Both now match.
- kexec-old-to-new after the ESP migration — *Status: fixed (inv165).* The old 61b3e85 kernel booted from its `\EFI\Forge\` disk and kexec'd, but the new generation 1 kernel read that disk's init.elf through the `EFI/Incudela -> EFI/Forge` alias and panicked `init.elf contents differ`: the init.elf on an unmigrated disk is the old build's (15128 bytes, "Forge user program"), not this build's (15136 bytes). fs_mount now records an old-layout disk (`fs_oldesp`), and fs_test runs that init.elf and says it is from the build that wrote `\EFI\Forge\`; the identity panic stays for `\EFI\Incudela\` disks. With that fixed, the next check panicked `read through blkd failed`: blk_same compared the user-mode driver's read with this build's embedded init too. On an old-layout disk it now compares with the in-kernel driver's read from fs_test (`init_ref`), so the user-mode driver is still checked byte for byte. kexec-old-to-new requires the new line, so the migration path is covered rather than skipped. (Its forgefs boots also waited 180 s each because `...PANIC: ...` is not at line start; that was a symptom of the seal bug, not a hang.)
- False HANGs from box suspensions (inv167 kexec-old-to-new, inv171 bootpol2) — *Status: fixed (2026-11-16).* Both dumps show a guest idle at the shell prompt (all LAPIC IRR/ISR empty, timers counting, IOAPIC keyboard and serial pins unmasked, no Remote IRR; the inv171 shell had already printed `sh$ ` after `busybox sleep 1` exited), and both claim more silence than the QEMU process had lived: inv167 "no output for 60 s" with QEMU 42 s old, inv171 "172 s" with QEMU 34 s old (ps ELAPSED, which follows the box's CLOCK_BOOTTIME). The box is a VM that is suspended whole at times (its kernel logs "crng reseeded due to virtual machine fork", one at 11:33 CST next to the inv171 dump). tests/os/boot.cud measured silence with time.time(): its freeze check ran at the top of each loop pass, so a suspension landing after that check (in the drain, or in a send, which reset the pass timer) went straight into `now - tlast` and the same pass declared HANG on resume, before the guest had run again. The real guest silence was about 12 s in both. The harness clock is now CLOCK_MONOTONIC (`clk()`), which does not advance across a suspension (checked: across the 12:00:05 CST VM fork the wall clock jumped 54.2 s against both CLOCK_MONOTONIC and CLOCK_BOOTTIME), suspensions are logged from the wall/monotonic offset, and the >3 s pass check also runs right before a HANG is declared. The 60 s stall, the timeouts, the retry rule (a HANG always fails) and every expected line are unchanged; boot.py follows; self-test `boot-harness monotonic-clock` added. The interrupt capture (next entry) is what ruled out a lost interrupt.
- Hang dumps without interrupt state — *Status: done (2026-11-16).* inv167's O0 kexec-old-to-new hang (input typed after kexec never echoed; all vCPUs had IF=1, three in idle_loop, one in SHA-256 for image_verify) could not show whether IRQ1 was masked or undelivered. The boot harness (tests/os/boot.cud, boot.py reference) now appends `info pic`, `info irq` and `info lapic N` for every vCPU to `LOG.hangN`. The hang itself is still open.
- Hang dumps without guest input counters — *Status: done (2026-11-18).* inv203's O0 kernel-bios first-boot hang (forge-logs/hang-lapic-analysis.txt): the shell waited for the Enter of `hello Swap OK` typed on the PS/2 keyboard while `crash k 4` restarted kbdd; QEMU counted 99 IRQ1 against 115 in every passing boot (the missing 16 are exactly `ap OK<Enter>`), but the dump could not show what the guest had read. Each kernel now prints a `hang probe:` line at boot (the slid addresses of `kbd_irqs`, the new `ps2_rd`, the input journal, tty and tick counters; examples/kernel/kbd.cudi), and tests/os/boot.cud reads them on cpu 0 into `LOG.hangN` (self-test `hang-probe-parse`; `os/hang-probe-live` runs the reads at KERNEL OK). boot.py, the reference, is not extended (no new Python). The hang itself is still open: the kernel fix comes after these diagnostics, as its own batch.
- CPU 0 interrupts-off watch — *Status: done (2026-11-18), diagnostic only.* Hypothesis H1 for inv203 is that CPU 0, the only IRQ1 target (IOAPIC dest 0), took no interrupts for 2-3 s while the line was typed, so QEMU's 16-byte PS/2 queue overflowed. `on_lapic_timer` on CPU 0 now takes one `rdtsc` per tick (`i0_watch`, examples/kernel/apic.cudi): the LAPIC timer stays pending while IF=0, so the longest gap between two CPU 0 timer interrupts bounds the longest interrupts-off stretch to one tick. It is reset when the shell session starts and reported after it (`irq-off watch: cpu0 longest gap between timer interrupts N ms (at tick T), gaps over 250 ms: K`), and the hang probe carries `i0_max`, `i0_max_tick` and `i0_over`. Nothing in the kernel reads them, and no gap fails the boot; `os/irq-off-watch` needs the line and logs its numbers. Raw TSC time: a frozen or suspended box is a gap too. Unsafe report unchanged (168 / 659). Guest-not-running split (2026-11-19): in the kbs-s1 loaded stress three boots reported 125,847, 303,739 and 140,112 ms, each matching (within 0.3 s) the box freeze the harness measured in that boot (the guest TSC follows host time, the periodic LAPIC timer does not replay missed ticks); boots whose freeze fell outside the shell session showed normal gaps. Gaps of 5 s or more (`I0_STALL_MS`) are now counted apart (`i0_stalls`, `i0_stall_max`, line suffix `; guest not running (gaps of 5 s or more): S, longest M ms`) and kept out of `i0_max` and `i0_over`; the hang probe adds `i0_stalls`. Still diagnostic only; os/irq-off-watch now needs the full line.
- Test/debug and release kernel builds — *Status: done (2026-11-19, inv213).* The hang probe (`hang_probe_line`, now `kdbg_hang_probe`, and `probe_put`) and the KASLR test/debug hooks (the `KASLR: kernel image at ... (slide ...)` and `KASLR: big heap at ...` lines and the `unslid .text` mapping check) moved to examples/kernel/kdebug.cudi, which kernel.cud includes. `build/kernel-build --release` (and the reference `build.sh --release`) compiles kernel.cud with examples/kernel/krelease.cudi instead (empty `kdbg_*` hooks) into build/kernel-release/kernel.elf; the default build, kernel-next and the ISO the OS tests boot stay test/debug builds, so every OS test sees the same output. KASLR itself stays on in release (only its reporting and self-check are test/debug); `ktest_hooks` still gates syscalls 408/409 in both builds. Kernel instructions (`--fs-ssa`): test/debug 83,085 to 83,106 (the three hook calls), release 82,971; unsafe report unchanged (168 functions, 659 ops). Test: tests/kernel-release/run.sh (in run_tests.sh): the Cuditor and script release builds match byte for byte; the probe and layout strings are in build/kernel/kernel.elf and not in the release ELF; the release `kdbg_*` bodies make no call and load no string while the test/debug ones do; `kaslr_pick`, `kaslr_unmap` and the `ktest_hooks` references are in both (with krelease.cudi replaced by kdebug.cudi, 9 checks fail). Not covered: the release kernel is not booted by any test, and other boot lines still print addresses (`higher half: rip`, `page tables built: pml4 at`).
- 0.23.1 release-kernel hardening — *Status: done (2026-11-23, inv227).* The release kernel is now booted, not only
  inspected: tests/os/run.sh builds it (`build/kernel-build --release`) onto its own GRUB ISO and boots the BIOS path
  to `KERNEL OK` with the full kernel marker set the UEFI boots use (`os/kernel-release-bios`, one kexec into the test/debug
  kernel-next.elf), and `os/kernel-release-quiet` checks that its own generation printed none of the test/debug
  lines (expected results 50 to 52). Three more boot outputs became test/debug only: `page tables built: pml4 at`
  (`kdbg_paging`), `higher half: rip ..., rsp ...` (`kdbg_higher_half`; the slid rip gave away the image slide in
  release builds) and the CPU 0 interrupts-off watch: `i0_watch` (one `rdtsc` per CPU 0 timer tick), `i0_reset`
  and `i0_report` moved from apic.cudi into kdebug.cudi, called through `kdbg_tick0`, `kdbg_watch_reset` and
  `kdbg_watch_report`, whose krelease.cudi stubs are empty. tests/kernel-release checks the three strings are absent
  from the release ELF, the five new hooks are empty there and `i0_watch` is not compiled into it. The test/debug
  kernel (what the OS tests boot) prints exactly what it printed before; the unsafe report is unchanged.
- Data key independent of the wrap salt (fix) — *Status: done (2026-11-23, inv228).* `od_key_new` took the
  128-bit wrap salt stored in plain in objects.key from words 0..3 of the entropy digest and built the data key
  from the same words mixed with words 4..7 (`bswap(h_i) ^ h_(7-i)`), so reading the salt left the 256-bit data
  key only 128 unknown bits. Now the digest is only a PRF key: DK = HMAC(digest, "dkey"), salt =
  HMAC(digest, "wsalt"), and the digest is wiped. A store created before keeps its weaker data key until data-key
  rotation (planned, inv229) replaces it; the format
  is unchanged. tests/os/forgefs.sh `os/objstore-data-key-independent` unwraps DK on the host with openssl and
  checks the old relation holds for none of the four word pairs (it held for all four before the fix); expected
  results 52 to 53.
- Data-at-rest keys, batch 1a: RDSEED/RDRAND in the data key — *Status: done (2026-11-23, inv228).* `od_key_new`
  mixes up to `OD_HWN` = 32 RDSEED and 32 RDRAND words into its SHA-256 pool after the 512 TSC jitter samples,
  when CPUID reports them (RDRAND CPUID.1:ECX[30], RDSEED CPUID.(7,0):EBX[18]). `hw_rand` (cpux.cudi asm, `.byte`
  encodings, up to 64 tries with `pause`) returns the value and `hw_rand_ok`; a missing, 0, all-ones or repeated
  value is refused and counted, never mixed, and every word passes `nd_rand` (sites 5 and 6) like the jitter.
  The boot log reports the counts; `os/objstore-key-entropy` requires 32 + 32 with none refused under `-cpu max`
  (expected results 53 to 54). Kernel unsafe report unchanged (an extern call is not an unsafe op); asm-audit
  lists `hw_rand`.
- Data-at-rest keys, batch 1b: salted, iterated passphrase KDF (key slot v2) — *Status: done (2026-11-23, inv228).*
  The KEK was SHA-256("frge-kek" || passphrase): no salt, one hash per guess. Now crypt.cudi has PBKDF2-HMAC-SHA256
  (`pb_kdf`, the inner/outer HMAC states computed once and restored for each of the c iterations; known-answer
  vectors in tests/fs/crypt.cud at default, -O0, --fs-opt and --fs-ssa) and a new store's slot is v2: objects.key
  words 16..19 = 2, a 128-bit KDF salt (HMAC(digest, "ksalt"), independent of DK and the wrap salt), and
  `OD_KDF_ITERS` = 20000 (about 0.5 s on QEMU TCG; the boot log prints the ms). The count is read from the slot, so
  a later raise keeps old slots readable; 0 or above 2^24 is refused. `od_fwcfg_key` now keeps the raw passphrase
  in `od_uk`, which is wiped after `od_open`. A v1 slot (words 16..19 zero) still unlocks with the old KEK and the
  boot log names it legacy; it is not rewritten in place (a one-block rewrite of the only key slot is not
  crash-safe). Tests: `os/objstore-kdf-salted` (openssl PBKDF2 on the host gives the stored check value, the
  unsalted KEK does not) and `os/objstore-legacy-slot` (a host-written v1 slot for the same DK unlocks the persisted
  store; a mutation that drops the v1 path fails it); expected results 54 to 56. Kernel unsafe report unchanged.
- Data-at-rest keys, batch 2a: two-copy key file — *Status: done (2026-11-23, inv229).* The key slot was one block,
  `objects.key`, so any rewrite (passphrase change, v1-to-v2 upgrade) would have overwritten the only copy in
  place. Now `objects.keyb` is a second copy; a slot written since inv229 has a generation (word 20) and a SHA-256
  of its bytes 0..191 (words 24..27, detects a torn or corrupted copy; the check value still authenticates the
  key). `od_key_store` writes the copy that is not current, flushes, then writes the other; `od_key_load` takes
  the intact copy with the higher generation (the older copy's key is never tried) and `od_key_fix` rewrites a
  missing, damaged or older other copy from it. Pre-inv229 stores (one copy, words 20..27 zero) unlock as before
  and get `objects.keyb` at the first unlock. Found while writing it: a `u64[28]` parameter is a copy
  (copy-on-assign), so the first draft's `od_kread(name, s)` filled a copy and every store read as locked; the
  copies are now chosen by number. Tests: `os/objstore-key-two-copies`, `os/objstore-key-copy-repair` (one byte of
  `objects.key` flipped: unlocked from `objects.keyb`, `objects.key` rewritten), and `os/objstore-legacy-slot` now
  zeroes `objects.keyb` too; expected results 56 to 58.
- Data-at-rest keys, batch 2b: passphrase change — *Status: done (2026-11-23, inv229).* A boot that gets the current
  passphrase as fw_cfg `opt/forge/userkey` and a new one as `opt/forge/newkey` (`od_fwcfg_key(1)`, 8..64 bytes)
  rewraps the same data key after the unlock: a new entropy pool, fresh wrap and KDF salts, PBKDF2 of the new
  passphrase, the next generation, written by `od_key_store` (other copy first). The object log is not rewritten.
  Tests: `os/objstore-passphrase-change` (the host's PBKDF2 of the new passphrase gives the check value and the
  same data key; the old passphrase is locked and writes nothing; the new one reads the store) and
  `os/objstore-passphrase-change-crash` (a crash between the two copy writes: the old passphrase stays locked, the
  new one unlocks from `objects.keyb` and repairs `objects.key`; a kernel that ignores the generation fails it);
  forgefs.sh `boot` takes the new passphrase as a second argument; expected results 58 to 60.
- Data-at-rest keys, batch 2c: v1-to-v2 key slot upgrade — *Status: done (2026-11-23, inv229).* A v1 slot (the
  unsalted SHA-256 KEK of stores made before inv228) is upgraded at its first unlock: `od_key_load` rewraps the same
  data key under PBKDF2 of the same passphrase with fresh salts as the next generation through `od_key_store`
  (a passphrase change on a v1 slot does the same under the new passphrase). The boot log reports the v1 unlock and
  the upgrade. `os/objstore-legacy-slot` now checks the upgrade on the host (both copies a generation-1 v2 slot,
  openssl PBKDF2 gives the check value, same data key) and that the next boot unlocks it as v2 and rewrites nothing.
  The boot log's key file line names the generation and copy that were unlocked (`od_kg0`, `od_kc0`).
- Data-at-rest keys, batch 3a: crash-safe data-key rotation — *Status: done (2026-11-24, inv231).* fw_cfg file
  `opt/forge/rotatedk` = `rotate-data-key` asks for it (`od_rk_req`). `od_rot_maybe` (end of `od_open`) draws a
  fresh independent data key from a new entropy pool and a fresh wrap salt (the KEK and KDF salt stay, so no
  passphrase is needed) and writes the rotating slot as the next generation through the two-copy write: the new
  data key wrapped in words 4..11, the old one in words 28..35 as DK_old XOR HMAC(KEK, "odk" || wrap salt), word 21
  = 1, the SHA-256 now over words 0..23 and 28..35 (`OD_KW` 28 -> 36 words). Then the counter is written under the
  new MAC key past the old high-water mark, every log block is rewritten through `od_put` under the new keys (a new
  slot each), and the final slot (generation + 1, old key cleared) is stored. While a slot is rotating, `od_slot_wc`
  and `od_ctr_load` accept a slot under either key (`od_lk` names the one that verified, and the block is decrypted
  under it), so a boot after a crash anywhere in the rewrite reads the whole store and resumes, rewriting every
  block again (idempotent). The rotation word is the durable progress mark: a crash before the first copy of the
  rotating slot is flushed leaves the old slot, after it the resume. A passphrase change or v1 upgrade on a rotating
  slot keeps the rotating fields (`od_slot_rot` in `od_slot_build`). `rotate-data-key:stop-after:N` stops after N
  blocks without the final slot, as a power loss would. Tests `os/objstore-dk-rotate`, `os/objstore-dk-rotate-crash`
  (stop after 30 and after 0 of 65 blocks); with old-key verification removed from `od_slot_wc` the crash test
  FAILs. The old physical slots of each block keep their old-key ciphertext until overwritten: a copy of the disk
  taken before still opens with the old key slot (see privacy.md limits).
- Data-at-rest keys, batch 3b: pre-fix data keys rotated unasked — *Status: done (2026-11-24, inv231).*
  `od_wk_check` (in `od_rot_maybe`, on a slot that is not rotating) runs `od_dk_weak` on this store's data key: the
  derivation before 87b91fb made DK word 7-i = bswap(DK_i ^ bswap(h_i)) ^ h_i for the four 32-bit salt words h_i.
  A flagged key is rotated with reason 2 ("pre-fix data key"). A detector self-test first builds a key the old
  way (`od_wk_h`, into `od_dk1`) that must be flagged and must not be after one bit flips; on failure nothing is
  rotated unasked. Test `os/objstore-dk-prefix-rotate` writes such a slot from the host (same KEK); the host
  cannot re-encrypt the log, so the store opens empty there and the boot ends at the history check after the
  rotation. With the reason-2 branch disabled the test FAILs.
- forgefs key-copy offsets empty when the wrap salt holds a newline byte (inv230 OS run) — *Status: fixed (2026-11-24).* The inv230 standalone OS run failed `os/objstore-passphrase-change-crash` (`offsets ''`) and `os/objstore-dk-prefix-rotate` (boot 22 still saw the generation-1 slot). Root cause in tests/os/forgefs.sh (since inv229): `KOFFS`, the offsets of the two key copies in nv.img, came from `grep -obUaP` of the slot's first 32 bytes; grep matches within lines, so a pattern holding a 0x0a byte never matches, and bytes 16..31 are the random wrap salt (about 6% of searches). With `KOFFS` empty, `kput` returned 1 (crash test FAIL), and the pre-fix key test of the data-key rotation batch (inv231), which reuses the offsets, wrote nothing and booted the original slot. Fix: `koffs` greps bytes 0..15 only (magic and uid, never 0x0a) and keeps the candidates whose 32 bytes match, which also rejects stale copies with another salt. Checked on synthetic images: a salt with 0x0a (old search empty, `koffs` finds both copies), a salt without it (both agree), and a stale copy with the same 16-byte prefix (rejected). Test harness only; no test loosened.
- xHCI keyboard silent after the switch to MSI-X (inv230 precheck `os/drivers`) — *Status: fixed (2026-11-23).* The inv230 OS precheck failed `os/drivers` once with only `hello: args = 'usb'` missing: the shell printed `sh$ `, the host typed `hello usb`, and nothing reached the tty. It reproduced under 7 CPU hogs (load run L1, then diag run D28 of 49; unloaded 5 of 5 passed). A monitor dump of the failing boot (forge-logs/drv230-D28/dump.txt) showed xh_irqs 0, xh_keys 0, tty_pushed 0, the event ring index stuck at 0x1e with Transfer Events for the keyboard endpoint queued there, IMAN IP+IE, USBSTS.EINT, ERDP with Event Handler Busy set, and xh_kbd_last 0x28 (the polled check's last report was Enter still pressed); passing boots end at index 0x33 (21 more events: the Enter release and 20 reports of `hello usb`) with EHB clear. Root cause in `xh_irq_init` (examples/kernel/xhci.cudi): it drained the event ring and then set IMAN.IE and USBCMD.INTE. The Enter release report, when it was posted between the drain and IE, set EHB and IP without an interrupt (IE off); the IMAN write then cleared IP, and a controller with EHB set sends no MSI-X for later events (QEMU's xhci_intr_raise returns early while EHB is set), so the keyboard went silent for good. Fix: enable IMOD, IE and INTE first, then drain under rq_lock; the drain's ERDP write clears EHB, and the controller raises again if events are still queued. Evidence: with a 400 ms delay inserted after the old drain, 2 of 3 boots failed with the D28 signature; with the same delay between INTE and the new drain, 4 of 4 passed; the fixed kernel without the delay passed os/drivers in 31 of 31 boots under 7 hogs (forge-logs/drv230-F1..F31). Not related to the data-key rotation commits (gated as inv231): that boot has no Incudela FS. Unsafe report unchanged (168 / 659).
- stop-machine park race (kbs-s1 boot 30 kernel panic) — *Status: fixed (2026-11-19).* The loaded keyboard stress (forge-harness/kbdstress.sh, 7 CPU hogs) panicked once in 30 boots: three `EXCEPTION #UD` at `sys_getppid+0` in the generation-1 kernel's livepatch test, the 5-byte entry that `lp_write5` rewrites under stop-machine. Root cause in `tlb_poll` (examples/kernel/cpux.cudi): a CPU parked for round g waits `while tlb_park == g` and answers requests inside the wait; when the initiator ended g and began g' (livepatch issues back-to-back rounds) while that vCPU was descheduled, it answered g' (so it was counted as parked), then saw `tlb_park` = g' != g, left the loop and ran while the text was rewritten; TCG decoded a mixed instruction. Fix: an answer given inside the wait re-reads `tlb_park` and, if it is a new non-zero round, stays parked for it (and halts if it is the kexec round). Regression: `stop_machine_stress` now checks in each of its 3000 back-to-back rounds that the three lock hammers on the other CPUs do not advance between `stop_machine_begin` and `stop_machine_end` and panics otherwise (`no CPU ran while parked` is in run.sh's K). Evidence (forge-harness/smxrepro.sh, 7 hogs, BIOS boot to the stress verdict): test without the fix 40 of 40 boots FAILED (2-15 escapes per 3000 rounds); with the fix 40 of 40 OK. Unsafe report unchanged (168 / 659).
- Test-count gap between O2 and O0 runs — *Status: fixed.* In inv83, O2 reported 638 passes and O0 624, both with 0 FAIL. Fourteen os/ and dwarf/ result lines were missing from the O0 log in an alternating pattern, and one line was cut off mid-write (`full redraPASS`): output from `tests/os/run.sh` was lost inside the `r=$(...)` pipe capture, not skipped. A watcher during the next run saw O_NONBLOCK only on QEMU's own serial pipes, so the exact writer that dropped bytes was not identified. Fix (run_tests.sh): (1) capture `tests/os/run.sh` through a regular file (`build/os-results.txt`) instead of a pipe; (2) new check `os/result-count` FAILs if any name listed in `tests/os/expected-results.txt` (32 results) is missing, so lost output can never look like a passing run; (3) a second, smaller gap: the fas artifact round-trip globbed `build/os/*.s`, which existed only after an earlier OS run (boot.s), so run_tests now compiles the boot harness to `build/os/boot.s` first and both runs check the same set.
- Exact `__powfits` (float literals 1e16..1e22, typed `**`) — *Status: done.* Found while probing c2cud step 5: `e: f64 = 1e17` made cudc fail with `line 0: integer overflow`. The compiler folds a float literal with `float(text)`; `__fparse`'s Clinger fast path (<= 15 digits, |e10| <= 22) scales by `__ipow(10, k)`, and `__powfits` approximated the overflow test as bits(|a|) * b <= 62, so 10**16..10**18 (which fit) were rejected, and so was every typed-int `a ** b` past that bound. It now multiplies step by step against 2**62 - 1, the small-int limit (at most 62 steps for |a| >= 2); a first draft bounded by 2**63 - 1 let 2**62 .. 2**63 - 1 take the small-int path, which tests/bigints.cud (O2 and ast-pretty-semantic) caught: `2 ** 62` printed garbage and sums of it lost their bigint promotion. Regression tests/pow_fits.cud (typed powers up to 10**18, 3**39, 2**61, 7**22, and `2 ** 62` .. `2 ** 63` staying exact as bigints; literals and `float()` of 1e16..4e22). Two-pass reseed (prelude change), pinned in seed/seed.sha256 and reproduced byte-for-byte by build.sh (SEED OK, SEED TOOLS OK).

## Version 2 (after 1.0)

Ideas that are not part of 1.0 go here, not into the phases above. The v1 reservations keep room for them.
- **Allocation-effect enforcement**: check the reserved `noalloc`, `noio` and `noreclaim` effects.
- **Crash-takeover standby kernel**: a second kernel kept loaded that takes over the machine when the running one panics.
- **Multi-tenant GPU isolation**: GPU contexts isolated per app, with their own address spaces (the reserved
  address-space ID in device grants).
- **Free-threaded Python beyond the ABI switch**: running CPython without the GIL, beyond moving the bindings to abi3.
