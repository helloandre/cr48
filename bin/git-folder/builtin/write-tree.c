/*
 * GIT - The information manager from hell
 *
 * Copyright (C) Linus Torvalds, 2005
 */
#include "builtin.h"
#include "cache.h"
#include "tree.h"
#include "cache-tree.h"
#include "parse-options.h"

static const char * const write_tree_usage[] = {
	"git write-tree [--missing-ok] [--prefix=<prefix>/]",
	NULL
};

int cmd_write_tree(int argc, const char **argv, const char *unused_prefix)
{
	int flags = 0, ret;
	const char *prefix = NULL;
	unsigned char sha1[20];
	const char *me = "git-write-tree";
	struct option write_tree_options[] = {
		OPT_BIT(0, "missing-ok", &flags, "allow missing objects",
			WRITE_TREE_MISSING_OK),
		{ OPTION_STRING, 0, "prefix", &prefix, "<prefix>/",
		  "write tree object for a subdirectory <prefix>" ,
		  PARSE_OPT_LITERAL_ARGHELP },
		{ OPTION_BIT, 0, "ignore-cache-tree", &flags, NULL,
		  "only useful for debugging",
		  PARSE_OPT_HIDDEN | PARSE_OPT_NOARG, NULL,
		  WRITE_TREE_IGNORE_CACHE_TREE },
		OPT_END()
	};

	git_config(git_default_config, NULL);
	argc = parse_options(argc, argv, unused_prefix, write_tree_options,
			     write_tree_usage, 0);

	ret = write_cache_as_tree(sha1, flags, prefix);
	switch (ret) {
	case 0:
		printf("%s\n", sha1_to_hex(sha1));
		break;
	case WRITE_TREE_UNREADABLE_INDEX:
		die("%s: error reading the index", me);
		break;
	case WRITE_TREE_UNMERGED_INDEX:
		die("%s: error building trees", me);
		break;
	case WRITE_TREE_PREFIX_ERROR:
		die("%s: prefix %s not found", me, prefix);
		break;
	}
	return ret;
}
