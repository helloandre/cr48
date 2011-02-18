#include "cache.h"

int main(int ac, char **av)
{
	git_SHA_CTX ctx;
	unsigned char sha1[20];
	unsigned bufsz = 8192;
	char *buffer;

	if (ac == 2)
		bufsz = strtoul(av[1], NULL, 10) * 1024 * 1024;

	if (!bufsz)
		bufsz = 8192;

	while ((buffer = malloc(bufsz)) == NULL) {
		fprintf(stderr, "bufsz %u is too big, halving...\n", bufsz);
		bufsz /= 2;
		if (bufsz < 1024)
			die("OOPS");
	}

	git_SHA1_Init(&ctx);

	while (1) {
		ssize_t sz, this_sz;
		char *cp = buffer;
		unsigned room = bufsz;
		this_sz = 0;
		while (room) {
			sz = xread(0, cp, room);
			if (sz == 0)
				break;
			if (sz < 0)
				die_errno("test-sha1");
			this_sz += sz;
			cp += sz;
			room -= sz;
		}
		if (this_sz == 0)
			break;
		git_SHA1_Update(&ctx, buffer, this_sz);
	}
	git_SHA1_Final(sha1, &ctx);
	puts(sha1_to_hex(sha1));
	exit(0);
}
