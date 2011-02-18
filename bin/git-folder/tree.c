#include "cache.h"
#include "cache-tree.h"
#include "tree.h"
#include "blob.h"
#include "commit.h"
#include "tag.h"
#include "tree-walk.h"

const char *tree_type = "tree";

static int read_one_entry_opt(const unsigned char *sha1, const char *base, int baselen, const char *pathname, unsigned mode, int stage, int opt)
{
	int len;
	unsigned int size;
	struct cache_entry *ce;

	if (S_ISDIR(mode))
		return READ_TREE_RECURSIVE;

	len = strlen(pathname);
	size = cache_entry_size(baselen + len);
	ce = xcalloc(1, size);

	ce->ce_mode = create_ce_mode(mode);
	ce->ce_flags = create_ce_flags(baselen + len, stage);
	memcpy(ce->name, base, baselen);
	memcpy(ce->name + baselen, pathname, len+1);
	hashcpy(ce->sha1, sha1);
	return add_cache_entry(ce, opt);
}

static int read_one_entry(const unsigned char *sha1, const char *base, int baselen, const char *pathname, unsigned mode, int stage, void *context)
{
	return read_one_entry_opt(sha1, base, baselen, pathname, mode, stage,
				  ADD_CACHE_OK_TO_ADD|ADD_CACHE_SKIP_DFCHECK);
}

/*
 * This is used when the caller knows there is no existing entries at
 * the stage that will conflict with the entry being added.
 */
static int read_one_entry_quick(const unsigned char *sha1, const char *base, int baselen, const char *pathname, unsigned mode, int stage, void *context)
{
	return read_one_entry_opt(sha1, base, baselen, pathname, mode, stage,
				  ADD_CACHE_JUST_APPEND);
}

static int match_tree_entry(const char *base, int baselen, const char *path, unsigned int mode, const char **paths)
{
	const char *match;
	int pathlen;

	if (!paths)
		return 1;
	pathlen = strlen(path);
	while ((match = *paths++) != NULL) {
		int matchlen = strlen(match);

		if (baselen >= matchlen) {
			/* If it doesn't match, move along... */
			if (strncmp(base, match, matchlen))
				continue;
			/* pathspecs match only at the directory boundaries */
			if (!matchlen ||
			    baselen == matchlen ||
			    base[matchlen] == '/' ||
			    match[matchlen - 1] == '/')
				return 1;
			continue;
		}

		/* Does the base match? */
		if (strncmp(base, match, baselen))
			continue;

		match += baselen;
		matchlen -= baselen;

		if (pathlen > matchlen)
			continue;

		if (matchlen > pathlen) {
			if (match[pathlen] != '/')
				continue;
			if (!S_ISDIR(mode))
				continue;
		}

		if (strncmp(path, match, pathlen))
			continue;

		return 1;
	}
	return 0;
}

int read_tree_recursive(struct tree *tree,
			const char *base, int baselen,
			int stage, const char **match,
			read_tree_fn_t fn, void *context)
{
	struct tree_desc desc;
	struct name_entry entry;

	if (parse_tree(tree))
		return -1;

	init_tree_desc(&desc, tree->buffer, tree->size);

	while (tree_entry(&desc, &entry)) {
		if (!match_tree_entry(base, baselen, entry.path, entry.mode, match))
			continue;

		switch (fn(entry.sha1, base, baselen, entry.path, entry.mode, stage, context)) {
		case 0:
			continue;
		case READ_TREE_RECURSIVE:
			break;
		default:
			return -1;
		}
		if (S_ISDIR(entry.mode)) {
			int retval;
			char *newbase;
			unsigned int pathlen = tree_entry_len(entry.path, entry.sha1);

			newbase = xmalloc(baselen + 1 + pathlen);
			memcpy(newbase, base, baselen);
			memcpy(newbase + baselen, entry.path, pathlen);
			newbase[baselen + pathlen] = '/';
			retval = read_tree_recursive(lookup_tree(entry.sha1),
						     newbase,
						     baselen + pathlen + 1,
						     stage, match, fn, context);
			free(newbase);
			if (retval)
				return -1;
			continue;
		} else if (S_ISGITLINK(entry.mode)) {
			int retval;
			struct strbuf path;
			unsigned int entrylen;
			struct commit *commit;

			entrylen = tree_entry_len(entry.path, entry.sha1);
			strbuf_init(&path, baselen + entrylen + 1);
			strbuf_add(&path, base, baselen);
			strbuf_add(&path, entry.path, entrylen);
			strbuf_addch(&path, '/');

			commit = lookup_commit(entry.sha1);
			if (!commit)
				die("Commit %s in submodule path %s not found",
				    sha1_to_hex(entry.sha1), path.buf);

			if (parse_commit(commit))
				die("Invalid commit %s in submodule path %s",
				    sha1_to_hex(entry.sha1), path.buf);

			retval = read_tree_recursive(commit->tree,
						     path.buf, path.len,
						     stage, match, fn, context);
			strbuf_release(&path);
			if (retval)
				return -1;
			continue;
		}
	}
	return 0;
}

static int cmp_cache_name_compare(const void *a_, const void *b_)
{
	const struct cache_entry *ce1, *ce2;

	ce1 = *((const struct cache_entry **)a_);
	ce2 = *((const struct cache_entry **)b_);
	return cache_name_compare(ce1->name, ce1->ce_flags,
				  ce2->name, ce2->ce_flags);
}

int read_tree(struct tree *tree, int stage, const char **match)
{
	read_tree_fn_t fn = NULL;
	int i, err;

	/*
	 * Currently the only existing callers of this function all
	 * call it with stage=1 and after making sure there is nothing
	 * at that stage; we could always use read_one_entry_quick().
	 *
	 * But when we decide to straighten out git-read-tree not to
	 * use unpack_trees() in some cases, this will probably start
	 * to matter.
	 */

	/*
	 * See if we have cache entry at the stage.  If so,
	 * do it the original slow way, otherwise, append and then
	 * sort at the end.
	 */
	for (i = 0; !fn && i < active_nr; i++) {
		struct cache_entry *ce = active_cache[i];
		if (ce_stage(ce) == stage)
			fn = read_one_entry;
	}

	if (!fn)
		fn = read_one_entry_quick;
	err = read_tree_recursive(tree, "", 0, stage, match, fn, NULL);
	if (fn == read_one_entry || err)
		return err;

	/*
	 * Sort the cache entry -- we need to nuke the cache tree, though.
	 */
	cache_tree_free(&active_cache_tree);
	qsort(active_cache, active_nr, sizeof(active_cache[0]),
	      cmp_cache_name_compare);
	return 0;
}

struct tree *lookup_tree(const unsigned char *sha1)
{
	struct object *obj = lookup_object(sha1);
	if (!obj)
		return create_object(sha1, OBJ_TREE, alloc_tree_node());
	if (!obj->type)
		obj->type = OBJ_TREE;
	if (obj->type != OBJ_TREE) {
		error("Object %s is a %s, not a tree",
		      sha1_to_hex(sha1), typename(obj->type));
		return NULL;
	}
	return (struct tree *) obj;
}

int parse_tree_buffer(struct tree *item, void *buffer, unsigned long size)
{
	if (item->object.parsed)
		return 0;
	item->object.parsed = 1;
	item->buffer = buffer;
	item->size = size;

	return 0;
}

int parse_tree(struct tree *item)
{
	 enum object_type type;
	 void *buffer;
	 unsigned long size;

	if (item->object.parsed)
		return 0;
	buffer = read_sha1_file(item->object.sha1, &type, &size);
	if (!buffer)
		return error("Could not read %s",
			     sha1_to_hex(item->object.sha1));
	if (type != OBJ_TREE) {
		free(buffer);
		return error("Object %s not a tree",
			     sha1_to_hex(item->object.sha1));
	}
	return parse_tree_buffer(item, buffer, size);
}

struct tree *parse_tree_indirect(const unsigned char *sha1)
{
	struct object *obj = parse_object(sha1);
	do {
		if (!obj)
			return NULL;
		if (obj->type == OBJ_TREE)
			return (struct tree *) obj;
		else if (obj->type == OBJ_COMMIT)
			obj = &(((struct commit *) obj)->tree->object);
		else if (obj->type == OBJ_TAG)
			obj = ((struct tag *) obj)->tagged;
		else
			return NULL;
		if (!obj->parsed)
			parse_object(obj->sha1);
	} while (1);
}
