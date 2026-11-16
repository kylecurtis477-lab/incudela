# Preemptive kernel threads: spinlocks (atomics), per-CPU run queues with stealing (one rq_lock), per-CPU current and
# idle threads, round-robin on the 100 Hz LAPIC timer. The run-queue lock is held across the stack switch and
# released by whichever thread resumes, so a thread can never be picked up by another CPU half-saved.
T_READY = 0
T_RUNNING = 1
T_DEAD = 2
T_IDLE = 3
T_BLOCKED = 4
KTHREAD_STACK = 16384
KTHREAD_PAGES = 4

struct Thread:
    rsp: u64
    stack: u64
    kstack_top: u64
    state: u64
    id: u64
    next: u64
    cr3: u64
    cpus_seen: u64
    switches: u64
    iters: u64
    user: u64
    exit_code: u64
    proc: u64
    fpu: u64
    pin: u64
    wake_at: u64
    sc: u64[5]  # the syscall in progress (nr, a, b, c, d): a kexec handoff re-issues it
    kx_parked: u64
    spawn_drv: u64  # driver kind for proc_spawn* called by this thread (0: ordinary process)
    fsbase: u64  # 11.1b: user FS base (Linux TLS, arch_prctl ARCH_SET_FS); loaded on every switch to this thread
    ctid: u64  # 11.1b: Linux clear-child-tid address (zeroed and futex-woken when this thread exits)
    fx_as: u64  # 11.1b: futex key (address space, user address) while parked in fx_thr[]
    fx_addr: u64
    sig_mask: u64  # 11.1d: Linux blocked signals (bit n = signal n)
    sig_pend: u64  # 11.1d: thread-directed pending signals (tgkill)
    sig_rx: u64[2]  # rcx, r11 that rt_sigreturn restores (the iretq exit in user.fsi reads them via SF pad)
    rq_next: nown[Thread]  # Stage 3e: the run queue's owning link (wait queues keep using the raw `next`)
    rq_owned: u64  # 1 while an owner exists (run queue, current[] or idle_thr[]): thread_adopt refuses a second one

asm(
    ".text",
    # ctx_switch(save_rsp_slot, new_rsp): callee-saved registers live on each thread's stack
    ".globl ctx_switch",
    "ctx_switch:",
    "push %rbp", "push %rbx", "push %r12", "push %r13", "push %r14", "push %r15",
    "mov %rsp, (%rdi)",
    "mov %rsi, %rsp",
    "pop %r15", "pop %r14", "pop %r13", "pop %r12", "pop %rbx", "pop %rbp",
    "ret",
    # first switch into a new thread lands here with r12 = fn, r13 = arg
    "thread_start:",
    "call sched_tail",
    "mov %r13, %rdi",
    "call *%r12",
    "call thread_exit",
    "ud2",
    ".globl thread_start_addr",
    "thread_start_addr: lea thread_start(%rip), %rax",
    "ret"
)
extern def ctx_switch(save: u64, rsp: u64)
extern def thread_start_addr() -> u64

rq_lock: u64
# Stage 3e: the run queues own their READY threads. rq_head[q] owns the first one and each Thread.rq_next the next;
# rq_tail[q] is a non-owning view of the last one. current[cpu] owns the running thread and idle_thr[cpu] the idle
# thread while it is not running, so a thread has one owner at a time and moves between them by take/replace. A
# thread gets its owner from thread_adopt (thread_start_ready, wake_l, sched_cpu_init) and gives it up in
# schedule_l when it blocks (the raw wait-queue link holds it until wake_l adopts it again) or dies (thread_reap
# frees it through its handle). Everything is under rq_lock, as before.
rq_head: nown[Thread][8]  # Phase 8: one run queue per CPU (still under the one rq_lock)
rq_tail: u64[8]
rq_len: u64[8]
rq_enq: u64[8]
rq_steals: u64
current: nown[Thread][8]
idle_thr: nown[Thread][8]
next_tid: u64
ctx_switches: u64

def thread_release(t: nown[Thread]):
# an owner given up: to a raw handle (blocked or dead thread) or a none returned by replace
    return

def thread_addr(t: ref[Thread]) -> u64:
# a non-owning view of an owned thread (rq_tail, ctx_switch, cur_thread); it never becomes a second owner
    return u64(t)

@unsafe
def thread_adopt(t: ptr[Thread]) -> own[Thread]:
# the one raw-to-owner step: a thread handle becomes the scheduler's owner (rq_lock held, or the boot CPU alone)
    if t.rq_owned != 0:
        panic("thread_adopt: thread already owned")
    t.rq_owned = 1
    return own[Thread](t)

def rq_link_after(m: mut[Thread], t: own[Thread]):
    thread_release(replace(m.rq_next, t))

@unsafe
def rq_link(q: u64, t: own[Thread]):
# append t (and whatever chain hangs off it) to queue q; rq_tail[q] becomes t
    v = thread_addr(borrow(t))
    # the tail is owned by the chain under rq_head[q]; rq_lock makes the mut[Thread] below the only access to it
    if rq_tail[q] == 0:
        thread_release(replace(rq_head[q], t))
    else:
        rq_link_after(mut[Thread](ptr[Thread](rq_tail[q])), t)
    rq_tail[q] = v

def rq_push(t: own[Thread]):
# pinned threads go to their CPU's queue; others to the shortest queue, preferring the pushing CPU on ties
    n = ncpu_online
    if n == 0 or n > 8:
        n = 1
    q = lapic_cpu()
    if q >= n:
        q = 0
    if t.pin != 0:
        q = t.pin - 1
    else:
        i: u64 = 0
        while i < n:
            if rq_len[i] < rq_len[q]:
                q = i
            i += 1
    rq_link(q, t)
    rq_len[q] += 1
    rq_enq[q] += 1

def rq_take_first(q: u64, cpu: u64) -> nown[Thread]:
# the first thread of queue q that may run on cpu (unpinned or pinned to it); the others keep their order
    last = rq_tail[q]
    chain = take(rq_head[q])
    rq_tail[q] = 0
    while chain != 0:
        rest = take(chain.rq_next)
        p = chain.pin
        if p == 0 or p == cpu + 1:
            if rest != 0:
                rq_link(q, rest)
                rq_tail[q] = last
            else:
                thread_release(rest)
            return chain
        rq_link(q, chain)
        chain = rest
    return chain

def rq_pop(cpu: u64) -> nown[Thread]:
# own queue first; when empty, steal the first unpinned thread from the other queues (k = 1..7)
    k: u64 = 0
    while k < 8:
        q = (cpu + k) % 8
        if rq_head[q] != 0:
            t = rq_take_first(q, cpu)
            if t != 0:
                rq_len[q] -= 1
                if k != 0:
                    rq_steals += 1
                return t
            thread_release(t)
        k += 1
    none: nown[Thread]
    return none

# the matching cast for a stored Thread address (run queue, Proc.thread / xthr[], wait queues)
@unsafe
def as_thread(x: u64) -> ptr[Thread]:
    return ptr[Thread](x)

@unsafe
def cur_thread() -> ptr[Thread]:
# irqs off across the CPU-id read and the current[] load: a preemption (and migration)
# in between would return another CPU's thread (seen as cur_proc()==0 under chantest)
    f = irq_save()
    c = lapic_cpu()
    t = take(current[c])
    v: u64 = 0
    if t != 0:
        v = thread_addr(borrow(t))
    thread_release(replace(current[c], t))
    irq_restore(f)
    return ptr[Thread](v)

@unsafe
def thread_new(fn: u64, arg: u64) -> ptr[Thread]:
    t = ptr[Thread](kmalloc(sizeof(Thread)))
    memset(u64(t), 0, sizeof(Thread))
    t.stack = kstack_alloc(KTHREAD_PAGES)
    t.kstack_top = t.stack + KTHREAD_STACK
    t.id = atomic_fetch_add(addr(next_tid), 1, acq_rel) + 1
    t.cr3 = kernel_pml4
    t.fpu = fpu_area_new()
    top = t.kstack_top
    sp = top - 72
    vstore64(sp, 0)
    vstore64(sp + 8, 0)
    vstore64(sp + 16, arg)
    vstore64(sp + 24, fn)
    vstore64(sp + 32, 0)
    vstore64(sp + 40, 0)
    vstore64(sp + 48, thread_start_addr())
    vstore64(sp + 56, 0)
    vstore64(sp + 64, 0)
    t.rsp = sp
    t.state = T_READY
    return t

def thread_start_ready(t: ptr[Thread]):
    f = irq_save()
    spin_lock(addr(rq_lock))
    rq_push(thread_adopt(t))
    spin_unlock(addr(rq_lock))
    irq_restore(f)

def thread_spawn(fn: u64, arg: u64) -> ptr[Thread]:
    t = thread_new(fn, arg)
    thread_start_ready(t)
    return t

def thread_free(t: ptr[Thread]):
# only for T_DEAD threads: the lock round-trip guarantees the CPU that switched away from it is done
    f = irq_save()
    spin_lock(addr(rq_lock))
    st = t.state
    spin_unlock(addr(rq_lock))
    irq_restore(f)
    if st != T_DEAD:
        panic("thread_free: thread still alive")
    kstack_free(t.stack, KTHREAD_PAGES)
    fpu_area_free(t.fpu)
    kfree(u64(t))

@export
@unsafe
def sched_tail():
    spin_unlock(addr(rq_lock))
    sti()

def schedule(exiting: u64):
# interrupts are off (timer handler, yield, exit)
    spin_lock(addr(rq_lock))
    schedule_l(exiting)

@unsafe
def schedule_l(exiting: u64):
# rq_lock held, interrupts off; returns with rq_lock released. A T_BLOCKED caller is parked on a
# wait queue already and is not put back on the run queue. current[cpu] keeps cur's owner until the one
# transfer point below (replace by nxt), so cur_thread() is valid all the way to the switch.
    cpu = lapic_cpu()
    cur = cur_thread()
    if u64(cur) == 0:
        panic("schedule: no current thread")
    if exiting:
        cur.state = T_DEAD
    nxt = rq_pop(cpu)
    if nxt == 0:
        if cur.state == T_RUNNING or cur.state == T_IDLE:
            thread_release(nxt)
            spin_unlock(addr(rq_lock))
            return
        swap(nxt, idle_thr[cpu])
    if nxt == 0:
        thread_release(nxt)
        panic("schedule: no idle thread")
        return
    if nxt.state != T_IDLE:
        nxt.state = T_RUNNING
    nd_hook(ND_SCHED, cpu, thread_addr(borrow(nxt)))
    nxt.cpus_seen = nxt.cpus_seen | (u64(1) << cpu)
    nxt.switches += 1
    ctx_switches += 1
    tss[cpu].rsp0 = nxt.kstack_top
    percpu_kstack[cpu * 4] = nxt.kstack_top
    ncr3 = nxt.cr3
    nfs = nxt.fsbase
    nfpu = nxt.fpu
    nrsp = nxt.rsp
    # the transfer point: nxt's owner becomes current[cpu]; cur's owner goes back to the run queue (running), to
    # idle_thr (idle), or is given up (blocked: the wait queue's raw link; dead: thread_reap's handle)
    old = replace(current[cpu], nxt)
    if old != 0:
        if old.state == T_RUNNING:
            old.state = T_READY
            rq_push(old)
        elif old.state == T_IDLE:
            thread_release(replace(idle_thr[cpu], old))
        else:
            old.rq_owned = 0
            thread_release(old)
    else:
        thread_release(old)
    if ncr3 != cur.cr3:
        switch_cr3(cpu, ncr3)
    # 11.1b: the kernel never uses FS, so the MSR always holds the running thread's user FS base
    if nfs != cur.fsbase:
        wrmsr(MSR_FS_BASE, nfs)
    fpu_save(cur.fpu)
    fpu_restore(nfpu)
    ctx_switch(u64(addr(cur.rsp)), nrsp)
    spin_unlock(addr(rq_lock))

def yield_cpu():
    f = irq_save()
    schedule(0)
    irq_restore(f)

@export
@unsafe
def thread_exit():
    cli()
    schedule(1)
    panic("dead thread resumed")

def thread_guard_hit(cr2: u64) -> u64:
# called from #DF: if cr2 is in the current thread's guard page, return the rsp to restart it on
    if u64(cur_thread()) == 0:
        return 0
    t = cur_thread()
    if t.stack == 0 or cr2 < t.stack - PAGE or cr2 >= t.stack:
        return 0
    kstack_guard_faults += 1
    return t.kstack_top - 8

@export
def thread_overflow_exit():
# a kernel thread ran into its guard page: #DF moved it here, onto the top of its own stack
    puts("kernel thread ")
    put_u64(cur_thread().id)
    puts(" overflowed its stack into the guard page: killed, kernel carries on\n")
    thread_exit()

@unsafe
def idle_loop(arg: u64):
    while 1:
        sti()
        hlt()

@unsafe
def sched_cpu_init(cpu: u64, boot_ctx_is_idle: u64):
# the code running now becomes this CPU's boot thread: the idle thread on APs, `main` on the BSP
    t = ptr[Thread](kmalloc(sizeof(Thread)))
    memset(u64(t), 0, sizeof(Thread))
    t.cr3 = kernel_pml4
    t.fpu = fpu_area_new()
    t.cpus_seen = u64(1) << cpu
    if boot_ctx_is_idle:
        t.state = T_IDLE
        t.kstack_top = tss[cpu].rsp0
    else:
        t.state = T_RUNNING
        t.kstack_top = tss[cpu].rsp0
        t.id = atomic_fetch_add(addr(next_tid), 1, acq_rel) + 1
        it = thread_new(u64(idle_loop), 0)
        it.state = T_IDLE
        thread_release(replace(idle_thr[cpu], thread_adopt(it)))
    thread_release(replace(current[cpu], thread_adopt(t)))
    percpu_kstack[cpu * 4] = t.kstack_top

# ---- wait queues, sleeping mutexes, condition variables, timed sleep ----
# All wait-queue state is protected by rq_lock, so "check condition, enqueue, block" and "wake" can never
# interleave: no lost wakeups. Blocked threads use Thread.next as their queue link.
struct WaitQ:
    head: u64
    tail: u64

struct Mutex:
    locked: u64
    owner: u64
    q: WaitQ
    contended: u64

struct CondVar:
    q: WaitQ

sleepq: WaitQ
wq_blocks: u64
wq_wakes: u64

@unsafe
def wq_push(q: ptr[WaitQ], t: ptr[Thread]):
    t.next = 0
    if q.tail == 0:
        q.head = u64(t)
    else:
        ptr[Thread](q.tail).next = u64(t)
    q.tail = u64(t)

@unsafe
def wq_pop(q: ptr[WaitQ]) -> u64:
    t = q.head
    if t != 0:
        q.head = ptr[Thread](t).next
        if q.head == 0:
            q.tail = 0
    return t

def wq_block_l(q: ptr[WaitQ]):
# rq_lock held, irqs off: park the current thread on q and run something else; returns with rq_lock re-held
    cur = cur_thread()
    cur.state = T_BLOCKED
    wq_push(q, cur)
    wq_blocks += 1
    schedule_l(0)
    spin_lock(addr(rq_lock))

def wake_l(t: ptr[Thread]):
    t.state = T_READY
    rq_push(thread_adopt(t))
    wq_wakes += 1

@unsafe
def wq_wake_one_l(q: ptr[WaitQ]) -> u64:
    t = wq_pop(q)
    if t != 0:
        wake_l(ptr[Thread](t))
        return 1
    return 0

def wq_wake_all_l(q: ptr[WaitQ]) -> u64:
    n: u64 = 0
    while wq_wake_one_l(q):
        n += 1
    return n

def wq_wait(q: ptr[WaitQ]):
    f = irq_save()
    spin_lock(addr(rq_lock))
    wq_block_l(q)
    spin_unlock(addr(rq_lock))
    irq_restore(f)

def wq_wake_all(q: ptr[WaitQ]) -> u64:
    f = irq_save()
    spin_lock(addr(rq_lock))
    n = wq_wake_all_l(q)
    spin_unlock(addr(rq_lock))
    irq_restore(f)
    return n

def mutex_lock(m: ptr[Mutex]):
    f = irq_save()
    spin_lock(addr(rq_lock))
    cur = u64(cur_thread())
    if m.locked and m.owner == cur:
        panic("mutex_lock: recursive lock")
    while m.locked:
        m.contended += 1
        wq_block_l(addr(m.q))
    m.locked = 1
    m.owner = u64(cur_thread())
    spin_unlock(addr(rq_lock))
    irq_restore(f)

def mutex_unlock_l(m: ptr[Mutex]):
    if m.locked == 0 or m.owner != u64(cur_thread()):
        panic("mutex_unlock: not owner")
    m.locked = 0
    m.owner = 0
    wq_wake_one_l(addr(m.q))

def mutex_unlock(m: ptr[Mutex]):
    f = irq_save()
    spin_lock(addr(rq_lock))
    mutex_unlock_l(m)
    spin_unlock(addr(rq_lock))
    irq_restore(f)

def cond_wait(c: ptr[CondVar], m: ptr[Mutex]):
# atomically release m and sleep on c, then re-acquire m
    f = irq_save()
    spin_lock(addr(rq_lock))
    mutex_unlock_l(m)
    wq_block_l(addr(c.q))
    spin_unlock(addr(rq_lock))
    irq_restore(f)
    mutex_lock(m)

def cond_signal(c: ptr[CondVar]):
    f = irq_save()
    spin_lock(addr(rq_lock))
    wq_wake_one_l(addr(c.q))
    spin_unlock(addr(rq_lock))
    irq_restore(f)

def cond_broadcast(c: ptr[CondVar]):
    wq_wake_all(addr(c.q))

def sleep_ticks(n: u64):
    f = irq_save()
    spin_lock(addr(rq_lock))
    cur = cur_thread()
    cur.wake_at = lapic_ticks + n
    wq_block_l(addr(sleepq))
    spin_unlock(addr(rq_lock))
    irq_restore(f)

@unsafe
def sleep_tick_l():
# cpu 0 timer, rq_lock held: wake every sleeper whose deadline passed
    prev: u64 = 0
    t = sleepq.head
    while t != 0:
        nx = ptr[Thread](t).next
        if ptr[Thread](t).wake_at <= lapic_ticks:
            if prev == 0:
                sleepq.head = nx
            else:
                ptr[Thread](prev).next = nx
            if sleepq.tail == t:
                sleepq.tail = prev
            wake_l(ptr[Thread](t))
        else:
            prev = t
        t = nx

def thread_reap(t: ptr[Thread]):
    while atomic_load(addr(t.state), acquire) != T_DEAD:
        yield_cpu()
    thread_free(t)
