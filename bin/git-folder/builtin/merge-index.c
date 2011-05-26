#include "builtin.h"
#include "run-command.h"

static const char *pgm;
static int one_shot, quiet;
static int err;

static int merge_entry(int pos, const char *path)
{
	int found;
	const char *arguments[] = { pgm, "", "", "", path, "", "", "", NULL };
	char hexbuf[4][60];
	char ownbuf[4][60];

	if (pos >= active_nr)
		die("git merge-index: %s not in the cache", path);
	found = 0;
	do {
		struct cache_entry *ce = active_cache[pos];
		int stage = ce_stage(ce);

		if (strcmp(ce->name, path))
			break;
		found++;
		strcpy(hexbuf[stage], sha1_to_hex(ce->sha1));
		sprintf(ownbuf[stage], "%o", ce->ce_mode);
		arguments[stage] = hexbuf[stage];
		arguments[stage + 4] = ownbuf[stage];
	} while (++pos < active_nr);
	if (!found)
		die("git merge-index: %s not in the cache", path);

	if (run_command_v_opt(arguments, 0)) {
		if (one_shot)
			err++;
		else {
			if (!quiet)
				die("merge program failed");
			exit(1);
		}
	}
	return found;
}

static void merge_file(const char *path)
{
	int pos = cache_name_pos(path, strlen(path));

	/*
	 * If it already exists in the cache as stage0, it's
	 * already merged and there is nothing to do.
	 */
	if (pos < 0)
		merge_entry(-pos-1, path);
}

static void merge_all(void)
{
	int i;
	for (i = 0; i < active_nr; i++) {
		struct cache_entry *ce = active_cache[i];
		if (!ce_stage(ce))
			continue;
		i += merge_entry(i, ce->name)-1;
	}
}

int cmd_merge_index(int argc, const char **argv, const char *prefix)
{
	int i, force_file = 0;

	/* Without this we cannot rely on waitpid() to tell
	 * what happened to our children.
	 */
	signal(SIGCHLD, SIG_DFL);

	if (argc < 3)
		usage("git merge-index [-o] [-q] <merge-program> (-a | [--] <filename>*)");

	read_cache();

	i = 1;
	if (!strcmp(argv[i], "-o")) {
		one_shot = 1;
		i++;
	}
	if (!strcmp(argv[i], "-q")) {
		quiet = 1;
		i++;
	}
	pgm = argv[i++];
	for (; i < argc; i++) {
		const char *arg = argv[i];
		if (!force_file && *arg == '-') {
			if (!strcmp(arg, "--")) {
				force_file = 1;
				continue;
			}
			if (!strcmp(arg, "-a")) {
				merge_all();
				continue;
			}
			die("git merge-index: unknown option %s", arg);
		}
		merge_file(arg);
	}
	if (err && !quiet)
		die("merge program failed");
	return err;
}
