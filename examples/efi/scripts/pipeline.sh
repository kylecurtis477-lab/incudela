# Item 9 follow-up: a BusyBox ash pipeline and an external command in the
# compat sandbox (docs/linux-compat.md). Builtins use fork+pipe; a simple
# external command uses vfork (Linux syscall 58). The manifest grants only
# /efi/incudela/docs, so the external image is a sealed copy of busybox at
# /efi/incudela/docs/busybox, not /efi/incudela/bin (bin stays denied).
echo "pipeline script start"
echo pipe-ok | while read x; do echo "got $x"; done
echo ext-ok | /efi/incudela/docs/busybox wc -c
/efi/incudela/docs/busybox echo external-ok
echo "pipeline script done"
