# Linux AF_PACKET `hard_header_len` race local root exploit (03390aa)

**Exploit author:** A. Ramos `<aramosf@gmail.com>` (Twitter:
[@aramosf](https://twitter.com/aramosf))

**Discovery and upstream fix:** Qihang Tang
`<q.h.hack.winter@gmail.com>`

**Type:** Linux kernel local privilege escalation

**Affected lineage:** kernels containing `b84bbaf7a6c8` without the correction
in `03390aa32e669cc4ecd7d34108e2e1afc13d689d`

**Validated vulnerable target:** upstream Linux commit
`92d3817649df2b0b6a008a686c8275c88d7ef594`, reporting
`7.2.0-rc3+`, x86-64, QEMU/KVM

**First fixed mainline tag:** `v7.2-rc7`

**Public identifier:** none found as of 2026-08-13

**Upstream fix:**
<https://github.com/torvalds/linux/commit/03390aa32e669cc4ecd7d34108e2e1afc13d689d>

**Original patch:**
<https://patch.msgid.link/20260805125729.19220-3-q.h.hack.winter@gmail.com>

## Summary

A race in `packet_snd()` allowed `dev->hard_header_len` to change between skb
reservation and allocation calculations. A raw-packet send could consequently
copy userspace data before `skb->head`. The exploit uses an unprivileged user
and network namespace, a bonding layout transition and a FUSE copy gate to
make the write deterministic enough to corrupt an adjacent multicast filter.

The resulting kernel heap disclosure recovers the KASLR slide and locates a
controlled IPv6 txoption. Further bounded writes forge an AF_UNIX skb
`skb_shared_info` prefix and invoke `commit_creds()` with a build-specific fake
credential. A verified SUID transition removes the temporary helper, opens an
interactive shell in the initial namespaces and demonstrates UID/GID 0 by
running `id` there.

The current release is intentionally scoped to the exact upstream research
build documented in `README.md` and `kernel.config`; it is not presented as a
stock-distribution exploit.

## Reproduced comparison

- Vulnerable: commit `92d3817649df2b0b6a008a686c8275c88d7ef594` (`7.2.0-rc3+`),
  tested 2026-08-13. The fourth phase-1 placement corrupted the adjacent
  `sl_count`, the heap disclosure recovered the KASLR slide, the forged
  `skb_shared_info` reached `commit_creds(fake_cred)`, and the run ended with
  `uid=0(root) gid=0(root) groups=0(root)` in the initial namespaces. Full
  transcript: [`docs/example-output.txt`](docs/example-output.txt).
- Fixed: commit `03390aa32e669cc4ecd7d34108e2e1afc13d689d` (`7.2.0-rc5+`),
  identical configuration, tested 2026-08-12. All eight phase-1 placement
  attempts left `sl_count` unchanged, no disclosure or fake object was ever
  created, and the exploit exited with status 2 before reaching any
  corruption stage. No sanitizer report and no privilege artifact were left
  behind. Full transcript:
  [`docs/patched-negative-output.txt`](docs/patched-negative-output.txt).

## Archive contents

- `exploit.c`: main AF_PACKET `hard_header_len` race exploit.
- `root_helper.c`: SUID proof helper invoked after `commit_creds()` succeeds.
- `kernel.config`: exact build configuration of the validated target.
- `Makefile`: builds both static binaries into `build/`.
- `README.md`: vulnerability, exploitation process, affected/fixed versions,
  requirements, build and run instructions, references.
- `SUBMISSION.md`: this file.
- `docs/example-output.txt`: sanitized transcript of a successful run against
  the vulnerable commit.
- `docs/patched-negative-output.txt`: transcript of the same exploit against
  the fixed commit, showing the fail-closed abort.
- `assets/03390aa-packet-oob.cast` and `assets/03390aa-packet-oob.gif`: real
  Asciinema recording and rendered GIF of the exploit run.
- `scripts/record-live.sh`, `scripts/live-demo.exp`, `scripts/render-demo.sh`:
  helpers used to produce the Asciinema recording from a real QEMU guest.

## Build and run

```sh
make
./build/03390aa-packet-oob --exploit
```

Run only inside a disposable VM matching the documented target. Heap placement
is probabilistic, and a miss can panic or corrupt the guest.

## Public-exploit search

SearchSploit/Exploit-DB, Packet Storm, GitHub code and issue search, exact web
searches, NVD and the public identifier list were checked on 2026-08-12. No
matching public PoC or assigned record was found at that time.
