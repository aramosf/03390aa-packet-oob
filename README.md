# Linux AF_PACKET `hard_header_len` race: local root exploit (03390aa)

![Live QEMU exploit](assets/03390aa-packet-oob.gif)

This repository contains a build-specific local privilege-escalation exploit
for the Linux AF_PACKET race fixed by upstream commit
[`03390aa32e669cc4ecd7d34108e2e1afc13d689d`](https://github.com/torvalds/linux/commit/03390aa32e669cc4ecd7d34108e2e1afc13d689d).
The final chain starts as UID/GID 1000 with no supplementary groups, creates
its network topology inside unprivileged namespaces and obtains UID/GID 0 in
the initial user namespace.

The exploit was validated in QEMU/KVM against one exact upstream kernel build:
Linux `7.2.0-rc3+` at commit
[`92d3817649df2b0b6a008a686c8275c88d7ef594`](https://github.com/torvalds/linux/commit/92d3817649df2b0b6a008a686c8275c88d7ef594).
KASLR and AppArmor remain enabled, and the guest is not booted with `nokaslr`,
`nosmep` or `nosmap`.

> **Warning**
>
> This code intentionally corrupts kernel heap state and calls build-specific
> kernel addresses. A missed allocation can crash or corrupt the guest. Use it
> only in an isolated, disposable VM that you own. Do not run it on a host.

## Status and scope

This is a demonstrated upstream-kernel laboratory exploit, not yet a claim of
support for a stock distribution package. The symbol addresses, credential
layout and AppArmor blob used by `exploit.c` match the exact validated build.
Running the binary on another build without adapting and revalidating those
values is unsafe.

As of **2026-08-13**, no public vulnerability identifier was associated with
the fix. The repository therefore uses the abbreviated fix hash as its stable
name rather than inventing an identifier.

## Vulnerability

`packet_snd()` used to read `dev->hard_header_len` more than once while
allocating and constructing a raw-packet skb. Concurrent device
reconfiguration could make the saved reservation larger than the value used
for the allocation. The later negative `skb_reserve()` movement then placed
`skb->data` before `skb->head`, and `copy_from_iter_full()` wrote attacker data
out of bounds before the skb allocation.

The PoC creates a bonding device whose active slave can be changed between a
deep IP6GRE stack and a lower-header-length VXLAN-GPE stack. A FUSE-backed
userspace buffer stops `packet_snd()` after the first header-length decision.
While it is blocked, the PoC changes the bond layout and then releases the
copy, making the vulnerable kernel allocate with one value and reserve with
the other.

The same consistency problem existed in `packet_sendmsg_spkt()`. The upstream
fix saves the header length once and adds `LL_RESERVED_SPACE_EX()` so every
allocation and construction decision uses that saved value. The separate
SOCK_DGRAM issue explicitly mentioned by the commit is outside this PoC.

The vulnerability and fix were reported by **Qihang Tang**
`<q.h.hack.winter@gmail.com>`. The
[original patch submission](https://patch.msgid.link/20260805125729.19220-3-q.h.hack.winter@gmail.com)
contains the maintainer discussion and attribution.

## Affected and fixed versions

The upstream `Fixes:` tag points to
[`b84bbaf7a6c8`](https://github.com/torvalds/linux/commit/b84bbaf7a6c8)
(`packet: in packet_snd start writing at link layer allocation`). Kernel and
vendor versions remain affected until they contain the correcting commit or
an equivalent backport.

| State | Version or commit | Notes |
| --- | --- | --- |
| Introduced lineage | `b84bbaf7a6c8` | Commit named by the upstream `Fixes:` tag |
| Validated vulnerable | `92d3817649df` (`v7.2-rc3-719-g92d381764`) | Exact source used for the QEMU exploit |
| Corrected mainline | `03390aa32e66` | First included in the `v7.2-rc7` tag |

Do not decide vulnerability from `uname -r` alone. Vendor kernels routinely
backport networking fixes without changing to the corresponding mainline
version; inspect the source or package changelog for the fix.

## Validated target

| Property | Value |
| --- | --- |
| Source commit | `92d3817649df2b0b6a008a686c8275c88d7ef594` |
| Kernel release | `7.2.0-rc3+ #4 SMP PREEMPT` |
| Architecture | x86-64 |
| Compiler | GCC 15.2.0, GNU ld 2.46 |
| VM | QEMU/KVM, `-cpu host`, four vCPUs, 5 GiB RAM |
| Initial identity | UID/GID 1000, no supplementary groups |
| Final identity | UID/GID 0 in the initial namespaces |
| KASLR | Enabled; slide recovered from the kernel disclosure |
| LSM | AppArmor enabled; the forged credential carries a valid kernel label |
| Heap hardening | SLUB freelist randomization and hardening enabled |
| Instrumentation | UBSAN enabled; no KASAN |
| Boot overrides | No `nokaslr`, `nosmep`, `nosmap` or `nopti` |

The exact build configuration is preserved as
[`kernel.config`](kernel.config). UBSAN is part of the validated research
build, but it is not a prerequisite for the underlying bug. It does affect
the exact binary layout, which is one reason this release is build-specific.

## Requirements and laboratory changes

| Requirement | Validated state | Why it is needed |
| --- | --- | --- |
| `CONFIG_USER_NS`, `CONFIG_NET_NS` | Built in | Gives the ordinary user capabilities only inside private namespaces |
| Unprivileged user namespaces | Enabled | Allows `unshare(CLONE_NEWUSER | CLONE_NEWNET)` |
| `CONFIG_PACKET` | Built in | Reaches the vulnerable `packet_snd()` path |
| Bonding, IP6GRE and VXLAN | Built in | Creates the two competing link-layer layouts |
| IPv4 multicast/source filters | Built in | Provides the adjacent variable-length disclosure/write object |
| `CONFIG_FUSE_FS` and `/dev/fuse` | Built in; `/dev/fuse` mode 0666 in the guest | Stops the userspace copy at a controlled point |
| `CONFIG_RANDOMIZE_BASE` | Enabled | The PoC leaks `net_sysctl_root` and calculates the runtime slide |
| `CONFIG_SECURITY_APPARMOR` | Enabled | The fake credential supplies the matching valid label pointer |
| x86-64 exact build layout | Required | Kernel function and global addresses are link-time constants plus the leaked slide |

The init shell mounted a tmpfs on `/tmp`, mounted the repository through QEMU
9p and set `/dev/fuse` to mode 0666 before dropping to UID 1000. Those are lab
setup operations, not privileges obtained by the exploit. A distribution test
must independently verify its defaults, modules, sysctls, device permissions,
structure layouts and symbol addresses.

## Exploitation process

1. The original UID 1000 supervisor stays in the initial namespaces. Its child
   enters private user, network and mount namespaces and constructs the bond,
   IP6GRE and VXLAN-GPE topology.
2. The child sprays 984-byte IPv4 multicast source-filter objects and uses a
   FUSE-stalled AF_PACKET send to overwrite one adjacent filter's `sl_count`.
3. Reading that filter with `MCAST_MSFILTER` becomes a kernel heap disclosure.
   The PoC validates the corrupted count and finds a live `net_sysctl_root`
   pointer to recover the KASLR slide.
4. Persistent IPv6 hop-by-hop option objects carry a forged credential, an
   embedded fake skb and unique markers. The same disclosure locates one
   controlled object at runtime.
5. A second bounded overwrite resets `sl_count` to 240. A third overwrite
   expands it to 426 over an adjacent AF_UNIX skb, turning source additions
   into a controlled write over the skb's `skb_shared_info` prefix.
6. The forged shared-info data selects `msg_zerocopy_ubuf_ops`; releasing the
   target skb reaches a controlled callback whose destructor is
   `commit_creds(fake_cred)`.
7. The child, now UID/EUID 0 inside its namespace with a credential tied to the
   initial user namespace, installs a verified root-owned mode-4755 helper in
   the initial mount namespace.
8. The original supervisor verifies owner and mode, executes that helper and
   proves real UID/GID 0. The helper removes both temporary privilege
   artifacts and opens an interactive initial-namespace root shell. Running
   `id` in that shell confirms `uid=0(root) gid=0(root) groups=0(root)`.

The exploit child deliberately remains paused while the proof runs because a
live IPv6 option object backs the forged credential. Terminate the disposable
VM after the demonstration.

## Safety and reliability checks

Every stage validates the expected heap state before the next corruption. The
phase-1 leak is retried when no valid KASLR anchor is present. Phase 2 is
retried only when the old count is unchanged, and phase 3 is retried only when
the safe 250-source baseline remains intact. Any partial or unexpected state
causes a fail-closed abort before the fake callback is invoked.

The recorded revision completed on a fresh randomized boot. Its first three
phase-1 placements missed safely; the fourth produced the checked disclosure,
and the first phase-3 placement reached initial-namespace UID 0. Other fresh
boots aborted at an earlier checked stage. Reboot the VM from a clean snapshot
after every failure.

## Build

The Makefile produces two static sibling binaries. The exploit locates
`root_helper` relative to `/proc/self/exe`.

```sh
make
```

Equivalent commands:

```sh
mkdir -p build
gcc -O2 -g -Wall -Wextra -Werror -pthread -static \
  exploit.c -o build/03390aa-packet-oob
gcc -O2 -g -Wall -Wextra -Werror -pthread -static \
  root_helper.c -o build/root_helper
```

## Run

Copy or mount the complete `build/` directory into the disposable guest. From
the ordinary user account on the exact validated kernel:

```sh
id
grep -E '^Cap(Inh|Prm|Eff|Amb):' /proc/self/status
cat /proc/cmdline
./build/03390aa-packet-oob --exploit
```

A successful run ends with output equivalent to:

```text
[+] KASLR anchor net_sysctl_root=0xffffffff92283ca0; slide=0xe000000
...
[+] callback returned with uid=0 euid=0
[+] initial-namespace root artifact verified; executing proof
[ROOT] uid=0 euid=0 gid=0 egid=0
[ROOT] interactive initial-namespace shell ready
root@packet-oob-lab:/tmp/poc# id
uid=0(root) gid=0(root) groups=0(root)
root@packet-oob-lab:/tmp/poc#
```

The complete concise transcript from a real QEMU run is in
[`docs/example-output.txt`](docs/example-output.txt).

## Corrected-kernel negative control

The same configuration was also built at the exact correcting commit. On that
kernel, the deterministic send path does not overwrite the adjacent multicast
filter, no disclosure is created and the exploit exits before any fake object
or callback stage. The observed output is preserved in
[`docs/patched-negative-output.txt`](docs/patched-negative-output.txt).

## Public-exploit check

Checked again on **2026-08-13** immediately before updating the private
repository. Exact hash and subject searches, broader `packet_snd` /
`hard_header_len` searches, SearchSploit/Exploit-DB, Packet Storm, GitHub code
and issue search, the public identifier list and NVD returned no matching PoC
or assigned record. Results containing the upstream fix were excluded. This
is a point-in-time search, not a guarantee that another exploit will not
appear later.

## References

- [Upstream fix](https://github.com/torvalds/linux/commit/03390aa32e669cc4ecd7d34108e2e1afc13d689d)
- [Original patch submission](https://patch.msgid.link/20260805125729.19220-3-q.h.hack.winter@gmail.com)
- [Mainline `v7.2-rc7` tag](https://github.com/torvalds/linux/releases/tag/v7.2-rc7)
- [`Fixes:` commit `b84bbaf7a6c8`](https://github.com/torvalds/linux/commit/b84bbaf7a6c8)
- [Validated vulnerable source commit](https://github.com/torvalds/linux/commit/92d3817649df2b0b6a008a686c8275c88d7ef594)

## Attribution and licensing

The exploit was written by **A. Ramos** `<aramosf@gmail.com>` (Twitter:
[@aramosf](https://twitter.com/aramosf)). Vulnerability discovery and the
upstream fix are credited to **Qihang Tang**
`<q.h.hack.winter@gmail.com>`.

`exploit.c` and `root_helper.c` are licensed under GPL-2.0-only, as identified
by their SPDX headers.
