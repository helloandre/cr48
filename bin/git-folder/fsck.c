#include "cache.h"
#include "object.h"
#include "blob.h"
#include "tree.h"
#include "tree-walk.h"
#include "commit.h"
#include "tag.h"
#include "fsck.h"

static int fsck_walk_tree(struct tree *tree, fsck_walk_func walk, void *data)
{
	struct tree_desc desc;
	struct name_entry entry;
	int res = 0;

	if (parse_tree(tree))
		return -1;

	init_tree_desc(&desc, tree->buffer, tree->size);
	while (tree_entry(&desc, &entry)) {
		int result;

		if (S_ISGITLINK(entry.mode))
			continue;
		if (S_ISDIR(entry.mode))
			result = walk(&lookup_tree(entry.sha1)->object, OBJ_TREE, data);
		else if (S_ISREG(entry.mode) || S_ISLNK(entry.mode))
			result = walk(&lookup_blob(entry.sha1)->object, OBJ_BLOB, data);
		else {
			result = error("in tree %s: entry %s has bad mode %.6o\n",
					sha1_to_hex(tree->object.sha1), entry.path, entry.mode);
		}
		if (result < 0)
			return result;
		if (!res)
			res = result;
	}
	return res;
}

static int fsck_walk_commit(struct commit *commit, fsck_walk_func walk, void *data)
{
	struct commit_list *parents;
	int res;
	int result;

	if (parse_commit(commit))
		return -1;

	result = walk((struct object *)commit->tree, OBJ_TREE, data);
	if (result < 0)
		return result;
	res = result;

	parents = commit->parents;
	while (parents) {
		result = walk((struct object *)parents->item, OBJ_COMMIT, data);
		if (result < 0)
			return result;
		if (!res)
			res = result;
		parents = parents->next;
	}
	return res;
}

static int fsck_walk_tag(struct tag *tag, fsck_walk_func walk, void *data)
{
	if (parse_tag(tag))
		return -1;
	return walk(tag->tagged, OBJ_ANY, data);
}

int fsck_walk(struct object *obj, fsck_walk_func walk, void *data)
{
	if (!obj)
		return -1;
	switch (obj->type) {
	case OBJ_BLOB:
		return 0;
	case OBJ_TREE:
		return fsck_walk_tree((struct tree *)obj, walk, data);
	case OBJ_COMMIT:
		return fsck_walk_commit((struct commit *)obj, walk, data);
	case OBJ_TAG:
		return fsck_walk_tag((struct tag *)obj, walk, data);
	default:
		error("Unknown object type for %s", sha1_to_hex(obj->sha1));
		return -1;
	}
}

/*
 * The entries in a tree are ordered in the _path_ order,
 * which means that a directory entry is ordered by adding
 * a slash to the end of it.
 *
 * So a directory called "a" is ordered _after_ a file
 * called "a.c", because "a/" sorts after "a.c".
 */
#define TREE_UNORDERED (-1)
#define TREE_HAS_DUPS  (-2)

static int verify_ordered(unsigned mode1, const char *name1, unsigned mode2, const char *name2)
{
	int len1 = strlen(name1);
	int len2 = strlen(name2);
	int len = len1 < len2 ? len1 : len2;
	unsigned char c1, c2;
	int cmp;

	cmp = memcmp(name1, name2, len);
	if (cmp < 0)
		return 0;
	if (cmp > 0)
		return TREE_UNORDERED;

	/*
	 * Ok, the first <len> characters are the same.
	 * Now we need to order the next one, but turn
	 * a '\0' into a '/' for a directory entry.
	 */
	c1 = name1[len];
	c2 = name2[len];
	if (!c1 && !c2)
		/*
		 * git-write-tree used to write out a nonsense tree that has
		 * entries with the same name, one blob and one tree.  Make
		 * sure we do not have duplicate entries.
		 */
		return TREE_HAS_DUPS;
	if (!c1 && S_ISDIR(mode1))
		c1 = '/';
	if (!c2 && S_ISDIR(mode2))
		c2 = '/';
	return c1 < c2 ? 0 : TREE_UNORDERED;
}

static int fsck_tree(struct tree *item, int strict, fsck_error error_func)
{
	int retval;
	int has_full_path = 0;
	int has_empty_name = 0;
	int has_zero_pad = 0;
	int has_bad_modes = 0;
	int has_dup_entries = 0;
	int not_properly_sorted = 0;
	struct tree_desc desc;
	unsigned o_mode;
	const char *o_name;

	init_tree_desc(&desc, item->buffer, item->size);

	o_mode = 0;
	o_name = NULL;

	while (desc.size) {
		unsigned mode;
		const char *name;

		tree_entry_extract(&desc, &name, &mode);

		if (strchr(name, '/'))
			has_full_path = 1;
		if (!*name)
			has_empty_name = 1;
		has_zero_pad |= *(char *)desc.buffer == '0';
		update_tree_entry(&desc);

		switch (mode) {
		/*
		 * Standard modes..
		 */
		case S_IFREG | 0755:
		case S_IFREG | 0644:
		case S_IFLNK:
		case S_IFDIR:
		case S_IFGITLINK:
			break;
		/*
		 * This is nonstandard, but we had a few of these
		 * early on when we honored the full set of mode
		 * bits..
		 */
		case S_IFREG | 0664:
			if (!strict)
				break;
		default:
			has_bad_modes = 1;
		}

		if (o_name) {
			switch (verify_ordered(o_mode, o_name, mode, name)) {
			case TREE_UNORDERED:
				not_properly_sorted = 1;
				break;
			case TREE_HAS_DUPS:
				has_dup_entries = 1;
				break;
			default:
				break;
			}
		}

		o_mode = mode;
		o_name = name;
	}

	retval = 0;
	if (has_full_path)
		retval += error_func(&item->object, FSCK_WARN, "contains full pathnames");
	if (has_empty_name)
		retval += error_func(&item->object, FSCK_WARN, "contains empty pathname");
	if (has_zero_pad)
		retval += error_func(&item->object, FSCK_WARN, "contains zero-padded file modes");
	if (has_bad_modes)
		retval += error_func(&item->object, FSCK_WARN, "contains bad file modes");
	if (has_dup_entries)
		retval += error_func(&item->object, FSCK_ERROR, "contains duplicate file entries");
	if (not_properly_sorted)
		retval += error_func(&item->object, FSCK_ERROR, "not properly sorted");
	return retval;
}

static int fsck_ident(char **ident, struct object *obj, fsck_error error_func)
{
	if (**ident == '<' || **ident == '\n')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - missing space before email");
	*ident += strcspn(*ident, "<\n");
	if ((*ident)[-1] != ' ')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - missing space before email");
	if (**ident != '<')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - missing email");
	(*ident)++;
	*ident += strcspn(*ident, "<>\n");
	if (**ident != '>')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - bad email");
	(*ident)++;
	if (**ident != ' ')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - missing space before date");
	(*ident)++;
	if (**ident == '0' && (*ident)[1] != ' ')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - zero-padded date");
	*ident += strspn(*ident, "0123456789");
	if (**ident != ' ')
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - bad date");
	(*ident)++;
	if ((**ident != '+' && **ident != '-') ||
	    !isdigit((*ident)[1]) ||
	    !isdigit((*ident)[2]) ||
	    !isdigit((*ident)[3]) ||
	    !isdigit((*ident)[4]) ||
	    ((*ident)[5] != '\n'))
		return error_func(obj, FSCK_ERROR, "invalid author/committer line - bad time zone");
	(*ident) += 6;
	return 0;
}

static int fsck_commit(struct commit *commit, fsck_error error_func)
{
	char *buffer = commit->buffer;
	unsigned char tree_sha1[20], sha1[20];
	struct commit_graft *graft;
	int parents = 0;
	int err;

	if (commit->date == ULONG_MAX)
		return error_func(&commit->object, FSCK_ERROR, "invalid author/committer line");

	if (memcmp(buffer, "tree ", 5))
		return error_func(&commit->object, FSCK_ERROR, "invalid format - expected 'tree' line");
	if (get_sha1_hex(buffer+5, tree_sha1) || buffer[45] != '\n')
		return error_func(&commit->object, FSCK_ERROR, "invalid 'tree' line format - bad sha1");
	buffer += 46;
	while (!memcmp(buffer, "parent ", 7)) {
		if (get_sha1_hex(buffer+7, sha1) || buffer[47] != '\n')
			return error_func(&commit->object, FSCK_ERROR, "invalid 'parent' line format - bad sha1");
		buffer += 48;
		parents++;
	}
	graft = lookup_commit_graft(commit->object.sha1);
	if (graft) {
		struct commit_list *p = commit->parents;
		parents = 0;
		while (p) {
			p = p->next;
			parents++;
		}
		if (graft->nr_parent == -1 && !parents)
			; /* shallow commit */
		else if (graft->nr_parent != parents)
			return error_func(&commit->object, FSCK_ERROR, "graft objects missing");
	} else {
		struct commit_list *p = commit->parents;
		while (p && parents) {
			p = p->next;
			parents--;
		}
		if (p || parents)
			return error_func(&commit->object, FSCK_ERROR, "parent objects missing");
	}
	if (memcmp(buffer, "author ", 7))
		return error_func(&commit->object, FSCK_ERROR, "invalid format - expected 'author' line");
	buffer += 7;
	err = fsck_ident(&buffer, &commit->object, error_func);
	if (err)
		return err;
	if (memcmp(buffer, "committer ", strlen("committer ")))
		return error_func(&commit->object, FSCK_ERROR, "invalid format - expected 'committer' line");
	buffer += strlen("committer ");
	err = fsck_ident(&buffer, &commit->object, error_func);
	if (err)
		return err;
	if (!commit->tree)
		return error_func(&commit->object, FSCK_ERROR, "could not load commit's tree %s", sha1_to_hex(tree_sha1));

	return 0;
}

static int fsck_tag(struct tag *tag, fsck_error error_func)
{
	struct object *tagged = tag->tagged;

	if (!tagged)
		return error_func(&tag->object, FSCK_ERROR, "could not load tagged object");
	return 0;
}

int fsck_object(struct object *obj, int strict, fsck_error error_func)
{
	if (!obj)
		return error_func(obj, FSCK_ERROR, "no valid object to fsck");

	if (obj->type == OBJ_BLOB)
		return 0;
	if (obj->type == OBJ_TREE)
		return fsck_tree((struct tree *) obj, strict, error_func);
	if (obj->type == OBJ_COMMIT)
		return fsck_commit((struct commit *) obj, error_func);
	if (obj->type == OBJ_TAG)
		return fsck_tag((struct tag *) obj, error_func);

	return error_func(obj, FSCK_ERROR, "unknown type '%d' (internal fsck error)",
			  obj->type);
}

int fsck_error_function(struct object *obj, int type, const char *fmt, ...)
{
	va_list ap;
	struct strbuf sb = STRBUF_INIT;

	strbuf_addf(&sb, "object %s:", obj->sha1?sha1_to_hex(obj->sha1):"(null)");

	va_start(ap, fmt);
	strbuf_vaddf(&sb, fmt, ap);
	va_end(ap);

	error("%s", sb.buf);
	strbuf_release(&sb);
	return 1;
}
