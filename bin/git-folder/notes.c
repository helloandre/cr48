#include "cache.h"
#include "notes.h"
#include "blob.h"
#include "tree.h"
#include "utf8.h"
#include "strbuf.h"
#include "tree-walk.h"
#include "string-list.h"
#include "refs.h"

/*
 * Use a non-balancing simple 16-tree structure with struct int_node as
 * internal nodes, and struct leaf_node as leaf nodes. Each int_node has a
 * 16-array of pointers to its children.
 * The bottom 2 bits of each pointer is used to identify the pointer type
 * - ptr & 3 == 0 - NULL pointer, assert(ptr == NULL)
 * - ptr & 3 == 1 - pointer to next internal node - cast to struct int_node *
 * - ptr & 3 == 2 - pointer to note entry - cast to struct leaf_node *
 * - ptr & 3 == 3 - pointer to subtree entry - cast to struct leaf_node *
 *
 * The root node is a statically allocated struct int_node.
 */
struct int_node {
	void *a[16];
};

/*
 * Leaf nodes come in two variants, note entries and subtree entries,
 * distinguished by the LSb of the leaf node pointer (see above).
 * As a note entry, the key is the SHA1 of the referenced object, and the
 * value is the SHA1 of the note object.
 * As a subtree entry, the key is the prefix SHA1 (w/trailing NULs) of the
 * referenced object, using the last byte of the key to store the length of
 * the prefix. The value is the SHA1 of the tree object containing the notes
 * subtree.
 */
struct leaf_node {
	unsigned char key_sha1[20];
	unsigned char val_sha1[20];
};

/*
 * A notes tree may contain entries that are not notes, and that do not follow
 * the naming conventions of notes. There are typically none/few of these, but
 * we still need to keep track of them. Keep a simple linked list sorted alpha-
 * betically on the non-note path. The list is populated when parsing tree
 * objects in load_subtree(), and the non-notes are correctly written back into
 * the tree objects produced by write_notes_tree().
 */
struct non_note {
	struct non_note *next; /* grounded (last->next == NULL) */
	char *path;
	unsigned int mode;
	unsigned char sha1[20];
};

#define PTR_TYPE_NULL     0
#define PTR_TYPE_INTERNAL 1
#define PTR_TYPE_NOTE     2
#define PTR_TYPE_SUBTREE  3

#define GET_PTR_TYPE(ptr)       ((uintptr_t) (ptr) & 3)
#define CLR_PTR_TYPE(ptr)       ((void *) ((uintptr_t) (ptr) & ~3))
#define SET_PTR_TYPE(ptr, type) ((void *) ((uintptr_t) (ptr) | (type)))

#define GET_NIBBLE(n, sha1) (((sha1[(n) >> 1]) >> ((~(n) & 0x01) << 2)) & 0x0f)

#define SUBTREE_SHA1_PREFIXCMP(key_sha1, subtree_sha1) \
	(memcmp(key_sha1, subtree_sha1, subtree_sha1[19]))

struct notes_tree default_notes_tree;

static struct string_list display_notes_refs;
static struct notes_tree **display_notes_trees;

static void load_subtree(struct notes_tree *t, struct leaf_node *subtree,
		struct int_node *node, unsigned int n);

/*
 * Search the tree until the appropriate location for the given key is found:
 * 1. Start at the root node, with n = 0
 * 2. If a[0] at the current level is a matching subtree entry, unpack that
 *    subtree entry and remove it; restart search at the current level.
 * 3. Use the nth nibble of the key as an index into a:
 *    - If a[n] is an int_node, recurse from #2 into that node and increment n
 *    - If a matching subtree entry, unpack that subtree entry (and remove it);
 *      restart search at the current level.
 *    - Otherwise, we have found one of the following:
 *      - a subtree entry which does not match the key
 *      - a note entry which may or may not match the key
 *      - an unused leaf node (NULL)
 *      In any case, set *tree and *n, and return pointer to the tree location.
 */
static void **note_tree_search(struct notes_tree *t, struct int_node **tree,
		unsigned char *n, const unsigned char *key_sha1)
{
	struct leaf_node *l;
	unsigned char i;
	void *p = (*tree)->a[0];

	if (GET_PTR_TYPE(p) == PTR_TYPE_SUBTREE) {
		l = (struct leaf_node *) CLR_PTR_TYPE(p);
		if (!SUBTREE_SHA1_PREFIXCMP(key_sha1, l->key_sha1)) {
			/* unpack tree and resume search */
			(*tree)->a[0] = NULL;
			load_subtree(t, l, *tree, *n);
			free(l);
			return note_tree_search(t, tree, n, key_sha1);
		}
	}

	i = GET_NIBBLE(*n, key_sha1);
	p = (*tree)->a[i];
	switch (GET_PTR_TYPE(p)) {
	case PTR_TYPE_INTERNAL:
		*tree = CLR_PTR_TYPE(p);
		(*n)++;
		return note_tree_search(t, tree, n, key_sha1);
	case PTR_TYPE_SUBTREE:
		l = (struct leaf_node *) CLR_PTR_TYPE(p);
		if (!SUBTREE_SHA1_PREFIXCMP(key_sha1, l->key_sha1)) {
			/* unpack tree and resume search */
			(*tree)->a[i] = NULL;
			load_subtree(t, l, *tree, *n);
			free(l);
			return note_tree_search(t, tree, n, key_sha1);
		}
		/* fall through */
	default:
		return &((*tree)->a[i]);
	}
}

/*
 * To find a leaf_node:
 * Search to the tree location appropriate for the given key:
 * If a note entry with matching key, return the note entry, else return NULL.
 */
static struct leaf_node *note_tree_find(struct notes_tree *t,
		struct int_node *tree, unsigned char n,
		const unsigned char *key_sha1)
{
	void **p = note_tree_search(t, &tree, &n, key_sha1);
	if (GET_PTR_TYPE(*p) == PTR_TYPE_NOTE) {
		struct leaf_node *l = (struct leaf_node *) CLR_PTR_TYPE(*p);
		if (!hashcmp(key_sha1, l->key_sha1))
			return l;
	}
	return NULL;
}

/*
 * How to consolidate an int_node:
 * If there are > 1 non-NULL entries, give up and return non-zero.
 * Otherwise replace the int_node at the given index in the given parent node
 * with the only entry (or a NULL entry if no entries) from the given tree,
 * and return 0.
 */
static int note_tree_consolidate(struct int_node *tree,
	struct int_node *parent, unsigned char index)
{
	unsigned int i;
	void *p = NULL;

	assert(tree && parent);
	assert(CLR_PTR_TYPE(parent->a[index]) == tree);

	for (i = 0; i < 16; i++) {
		if (GET_PTR_TYPE(tree->a[i]) != PTR_TYPE_NULL) {
			if (p) /* more than one entry */
				return -2;
			p = tree->a[i];
		}
	}

	/* replace tree with p in parent[index] */
	parent->a[index] = p;
	free(tree);
	return 0;
}

/*
 * To remove a leaf_node:
 * Search to the tree location appropriate for the given leaf_node's key:
 * - If location does not hold a matching entry, abort and do nothing.
 * - Copy the matching entry's value into the given entry.
 * - Replace the matching leaf_node with a NULL entry (and free the leaf_node).
 * - Consolidate int_nodes repeatedly, while walking up the tree towards root.
 */
static void note_tree_remove(struct notes_tree *t,
		struct int_node *tree, unsigned char n,
		struct leaf_node *entry)
{
	struct leaf_node *l;
	struct int_node *parent_stack[20];
	unsigned char i, j;
	void **p = note_tree_search(t, &tree, &n, entry->key_sha1);

	assert(GET_PTR_TYPE(entry) == 0); /* no type bits set */
	if (GET_PTR_TYPE(*p) != PTR_TYPE_NOTE)
		return; /* type mismatch, nothing to remove */
	l = (struct leaf_node *) CLR_PTR_TYPE(*p);
	if (hashcmp(l->key_sha1, entry->key_sha1))
		return; /* key mismatch, nothing to remove */

	/* we have found a matching entry */
	hashcpy(entry->val_sha1, l->val_sha1);
	free(l);
	*p = SET_PTR_TYPE(NULL, PTR_TYPE_NULL);

	/* consolidate this tree level, and parent levels, if possible */
	if (!n)
		return; /* cannot consolidate top level */
	/* first, build stack of ancestors between root and current node */
	parent_stack[0] = t->root;
	for (i = 0; i < n; i++) {
		j = GET_NIBBLE(i, entry->key_sha1);
		parent_stack[i + 1] = CLR_PTR_TYPE(parent_stack[i]->a[j]);
	}
	assert(i == n && parent_stack[i] == tree);
	/* next, unwind stack until note_tree_consolidate() is done */
	while (i > 0 &&
	       !note_tree_consolidate(parent_stack[i], parent_stack[i - 1],
				      GET_NIBBLE(i - 1, entry->key_sha1)))
		i--;
}

/*
 * To insert a leaf_node:
 * Search to the tree location appropriate for the given leaf_node's key:
 * - If location is unused (NULL), store the tweaked pointer directly there
 * - If location holds a note entry that matches the note-to-be-inserted, then
 *   combine the two notes (by calling the given combine_notes function).
 * - If location holds a note entry that matches the subtree-to-be-inserted,
 *   then unpack the subtree-to-be-inserted into the location.
 * - If location holds a matching subtree entry, unpack the subtree at that
 *   location, and restart the insert operation from that level.
 * - Else, create a new int_node, holding both the node-at-location and the
 *   node-to-be-inserted, and store the new int_node into the location.
 */
static int note_tree_insert(struct notes_tree *t, struct int_node *tree,
		unsigned char n, struct leaf_node *entry, unsigned char type,
		combine_notes_fn combine_notes)
{
	struct int_node *new_node;
	struct leaf_node *l;
	void **p = note_tree_search(t, &tree, &n, entry->key_sha1);
	int ret = 0;

	assert(GET_PTR_TYPE(entry) == 0); /* no type bits set */
	l = (struct leaf_node *) CLR_PTR_TYPE(*p);
	switch (GET_PTR_TYPE(*p)) {
	case PTR_TYPE_NULL:
		assert(!*p);
		if (is_null_sha1(entry->val_sha1))
			free(entry);
		else
			*p = SET_PTR_TYPE(entry, type);
		return 0;
	case PTR_TYPE_NOTE:
		switch (type) {
		case PTR_TYPE_NOTE:
			if (!hashcmp(l->key_sha1, entry->key_sha1)) {
				/* skip concatenation if l == entry */
				if (!hashcmp(l->val_sha1, entry->val_sha1))
					return 0;

				ret = combine_notes(l->val_sha1,
						    entry->val_sha1);
				if (!ret && is_null_sha1(l->val_sha1))
					note_tree_remove(t, tree, n, entry);
				free(entry);
				return ret;
			}
			break;
		case PTR_TYPE_SUBTREE:
			if (!SUBTREE_SHA1_PREFIXCMP(l->key_sha1,
						    entry->key_sha1)) {
				/* unpack 'entry' */
				load_subtree(t, entry, tree, n);
				free(entry);
				return 0;
			}
			break;
		}
		break;
	case PTR_TYPE_SUBTREE:
		if (!SUBTREE_SHA1_PREFIXCMP(entry->key_sha1, l->key_sha1)) {
			/* unpack 'l' and restart insert */
			*p = NULL;
			load_subtree(t, l, tree, n);
			free(l);
			return note_tree_insert(t, tree, n, entry, type,
						combine_notes);
		}
		break;
	}

	/* non-matching leaf_node */
	assert(GET_PTR_TYPE(*p) == PTR_TYPE_NOTE ||
	       GET_PTR_TYPE(*p) == PTR_TYPE_SUBTREE);
	if (is_null_sha1(entry->val_sha1)) { /* skip insertion of empty note */
		free(entry);
		return 0;
	}
	new_node = (struct int_node *) xcalloc(sizeof(struct int_node), 1);
	ret = note_tree_insert(t, new_node, n + 1, l, GET_PTR_TYPE(*p),
			       combine_notes);
	if (ret)
		return ret;
	*p = SET_PTR_TYPE(new_node, PTR_TYPE_INTERNAL);
	return note_tree_insert(t, new_node, n + 1, entry, type, combine_notes);
}

/* Free the entire notes data contained in the given tree */
static void note_tree_free(struct int_node *tree)
{
	unsigned int i;
	for (i = 0; i < 16; i++) {
		void *p = tree->a[i];
		switch (GET_PTR_TYPE(p)) {
		case PTR_TYPE_INTERNAL:
			note_tree_free(CLR_PTR_TYPE(p));
			/* fall through */
		case PTR_TYPE_NOTE:
		case PTR_TYPE_SUBTREE:
			free(CLR_PTR_TYPE(p));
		}
	}
}

/*
 * Convert a partial SHA1 hex string to the corresponding partial SHA1 value.
 * - hex      - Partial SHA1 segment in ASCII hex format
 * - hex_len  - Length of above segment. Must be multiple of 2 between 0 and 40
 * - sha1     - Partial SHA1 value is written here
 * - sha1_len - Max #bytes to store in sha1, Must be >= hex_len / 2, and < 20
 * Returns -1 on error (invalid arguments or invalid SHA1 (not in hex format)).
 * Otherwise, returns number of bytes written to sha1 (i.e. hex_len / 2).
 * Pads sha1 with NULs up to sha1_len (not included in returned length).
 */
static int get_sha1_hex_segment(const char *hex, unsigned int hex_len,
		unsigned char *sha1, unsigned int sha1_len)
{
	unsigned int i, len = hex_len >> 1;
	if (hex_len % 2 != 0 || len > sha1_len)
		return -1;
	for (i = 0; i < len; i++) {
		unsigned int val = (hexval(hex[0]) << 4) | hexval(hex[1]);
		if (val & ~0xff)
			return -1;
		*sha1++ = val;
		hex += 2;
	}
	for (; i < sha1_len; i++)
		*sha1++ = 0;
	return len;
}

static int non_note_cmp(const struct non_note *a, const struct non_note *b)
{
	return strcmp(a->path, b->path);
}

static void add_non_note(struct notes_tree *t, const char *path,
		unsigned int mode, const unsigned char *sha1)
{
	struct non_note *p = t->prev_non_note, *n;
	n = (struct non_note *) xmalloc(sizeof(struct non_note));
	n->next = NULL;
	n->path = xstrdup(path);
	n->mode = mode;
	hashcpy(n->sha1, sha1);
	t->prev_non_note = n;

	if (!t->first_non_note) {
		t->first_non_note = n;
		return;
	}

	if (non_note_cmp(p, n) < 0)
		; /* do nothing  */
	else if (non_note_cmp(t->first_non_note, n) <= 0)
		p = t->first_non_note;
	else {
		/* n sorts before t->first_non_note */
		n->next = t->first_non_note;
		t->first_non_note = n;
		return;
	}

	/* n sorts equal or after p */
	while (p->next && non_note_cmp(p->next, n) <= 0)
		p = p->next;

	if (non_note_cmp(p, n) == 0) { /* n ~= p; overwrite p with n */
		assert(strcmp(p->path, n->path) == 0);
		p->mode = n->mode;
		hashcpy(p->sha1, n->sha1);
		free(n);
		t->prev_non_note = p;
		return;
	}

	/* n sorts between p and p->next */
	n->next = p->next;
	p->next = n;
}

static void load_subtree(struct notes_tree *t, struct leaf_node *subtree,
		struct int_node *node, unsigned int n)
{
	unsigned char object_sha1[20];
	unsigned int prefix_len;
	void *buf;
	struct tree_desc desc;
	struct name_entry entry;
	int len, path_len;
	unsigned char type;
	struct leaf_node *l;

	buf = fill_tree_descriptor(&desc, subtree->val_sha1);
	if (!buf)
		die("Could not read %s for notes-index",
		     sha1_to_hex(subtree->val_sha1));

	prefix_len = subtree->key_sha1[19];
	assert(prefix_len * 2 >= n);
	memcpy(object_sha1, subtree->key_sha1, prefix_len);
	while (tree_entry(&desc, &entry)) {
		path_len = strlen(entry.path);
		len = get_sha1_hex_segment(entry.path, path_len,
				object_sha1 + prefix_len, 20 - prefix_len);
		if (len < 0)
			goto handle_non_note; /* entry.path is not a SHA1 */
		len += prefix_len;

		/*
		 * If object SHA1 is complete (len == 20), assume note object
		 * If object SHA1 is incomplete (len < 20), and current
		 * component consists of 2 hex chars, assume note subtree
		 */
		if (len <= 20) {
			type = PTR_TYPE_NOTE;
			l = (struct leaf_node *)
				xcalloc(sizeof(struct leaf_node), 1);
			hashcpy(l->key_sha1, object_sha1);
			hashcpy(l->val_sha1, entry.sha1);
			if (len < 20) {
				if (!S_ISDIR(entry.mode) || path_len != 2)
					goto handle_non_note; /* not subtree */
				l->key_sha1[19] = (unsigned char) len;
				type = PTR_TYPE_SUBTREE;
			}
			if (note_tree_insert(t, node, n, l, type,
					     combine_notes_concatenate))
				die("Failed to load %s %s into notes tree "
				    "from %s",
				    type == PTR_TYPE_NOTE ? "note" : "subtree",
				    sha1_to_hex(l->key_sha1), t->ref);
		}
		continue;

handle_non_note:
		/*
		 * Determine full path for this non-note entry:
		 * The filename is already found in entry.path, but the
		 * directory part of the path must be deduced from the subtree
		 * containing this entry. We assume here that the overall notes
		 * tree follows a strict byte-based progressive fanout
		 * structure (i.e. using 2/38, 2/2/36, etc. fanouts, and not
		 * e.g. 4/36 fanout). This means that if a non-note is found at
		 * path "dead/beef", the following code will register it as
		 * being found on "de/ad/beef".
		 * On the other hand, if you use such non-obvious non-note
		 * paths in the middle of a notes tree, you deserve what's
		 * coming to you ;). Note that for non-notes that are not
		 * SHA1-like at the top level, there will be no problems.
		 *
		 * To conclude, it is strongly advised to make sure non-notes
		 * have at least one non-hex character in the top-level path
		 * component.
		 */
		{
			char non_note_path[PATH_MAX];
			char *p = non_note_path;
			const char *q = sha1_to_hex(subtree->key_sha1);
			int i;
			for (i = 0; i < prefix_len; i++) {
				*p++ = *q++;
				*p++ = *q++;
				*p++ = '/';
			}
			strcpy(p, entry.path);
			add_non_note(t, non_note_path, entry.mode, entry.sha1);
		}
	}
	free(buf);
}

/*
 * Determine optimal on-disk fanout for this part of the notes tree
 *
 * Given a (sub)tree and the level in the internal tree structure, determine
 * whether or not the given existing fanout should be expanded for this
 * (sub)tree.
 *
 * Values of the 'fanout' variable:
 * - 0: No fanout (all notes are stored directly in the root notes tree)
 * - 1: 2/38 fanout
 * - 2: 2/2/36 fanout
 * - 3: 2/2/2/34 fanout
 * etc.
 */
static unsigned char determine_fanout(struct int_node *tree, unsigned char n,
		unsigned char fanout)
{
	/*
	 * The following is a simple heuristic that works well in practice:
	 * For each even-numbered 16-tree level (remember that each on-disk
	 * fanout level corresponds to _two_ 16-tree levels), peek at all 16
	 * entries at that tree level. If all of them are either int_nodes or
	 * subtree entries, then there are likely plenty of notes below this
	 * level, so we return an incremented fanout.
	 */
	unsigned int i;
	if ((n % 2) || (n > 2 * fanout))
		return fanout;
	for (i = 0; i < 16; i++) {
		switch (GET_PTR_TYPE(tree->a[i])) {
		case PTR_TYPE_SUBTREE:
		case PTR_TYPE_INTERNAL:
			continue;
		default:
			return fanout;
		}
	}
	return fanout + 1;
}

static void construct_path_with_fanout(const unsigned char *sha1,
		unsigned char fanout, char *path)
{
	unsigned int i = 0, j = 0;
	const char *hex_sha1 = sha1_to_hex(sha1);
	assert(fanout < 20);
	while (fanout) {
		path[i++] = hex_sha1[j++];
		path[i++] = hex_sha1[j++];
		path[i++] = '/';
		fanout--;
	}
	strcpy(path + i, hex_sha1 + j);
}

static int for_each_note_helper(struct notes_tree *t, struct int_node *tree,
		unsigned char n, unsigned char fanout, int flags,
		each_note_fn fn, void *cb_data)
{
	unsigned int i;
	void *p;
	int ret = 0;
	struct leaf_node *l;
	static char path[40 + 19 + 1];  /* hex SHA1 + 19 * '/' + NUL */

	fanout = determine_fanout(tree, n, fanout);
	for (i = 0; i < 16; i++) {
redo:
		p = tree->a[i];
		switch (GET_PTR_TYPE(p)) {
		case PTR_TYPE_INTERNAL:
			/* recurse into int_node */
			ret = for_each_note_helper(t, CLR_PTR_TYPE(p), n + 1,
				fanout, flags, fn, cb_data);
			break;
		case PTR_TYPE_SUBTREE:
			l = (struct leaf_node *) CLR_PTR_TYPE(p);
			/*
			 * Subtree entries in the note tree represent parts of
			 * the note tree that have not yet been explored. There
			 * is a direct relationship between subtree entries at
			 * level 'n' in the tree, and the 'fanout' variable:
			 * Subtree entries at level 'n <= 2 * fanout' should be
			 * preserved, since they correspond exactly to a fanout
			 * directory in the on-disk structure. However, subtree
			 * entries at level 'n > 2 * fanout' should NOT be
			 * preserved, but rather consolidated into the above
			 * notes tree level. We achieve this by unconditionally
			 * unpacking subtree entries that exist below the
			 * threshold level at 'n = 2 * fanout'.
			 */
			if (n <= 2 * fanout &&
			    flags & FOR_EACH_NOTE_YIELD_SUBTREES) {
				/* invoke callback with subtree */
				unsigned int path_len =
					l->key_sha1[19] * 2 + fanout;
				assert(path_len < 40 + 19);
				construct_path_with_fanout(l->key_sha1, fanout,
							   path);
				/* Create trailing slash, if needed */
				if (path[path_len - 1] != '/')
					path[path_len++] = '/';
				path[path_len] = '\0';
				ret = fn(l->key_sha1, l->val_sha1, path,
					 cb_data);
			}
			if (n > fanout * 2 ||
			    !(flags & FOR_EACH_NOTE_DONT_UNPACK_SUBTREES)) {
				/* unpack subtree and resume traversal */
				tree->a[i] = NULL;
				load_subtree(t, l, tree, n);
				free(l);
				goto redo;
			}
			break;
		case PTR_TYPE_NOTE:
			l = (struct leaf_node *) CLR_PTR_TYPE(p);
			construct_path_with_fanout(l->key_sha1, fanout, path);
			ret = fn(l->key_sha1, l->val_sha1, path, cb_data);
			break;
		}
		if (ret)
			return ret;
	}
	return 0;
}

struct tree_write_stack {
	struct tree_write_stack *next;
	struct strbuf buf;
	char path[2]; /* path to subtree in next, if any */
};

static inline int matches_tree_write_stack(struct tree_write_stack *tws,
		const char *full_path)
{
	return  full_path[0] == tws->path[0] &&
		full_path[1] == tws->path[1] &&
		full_path[2] == '/';
}

static void write_tree_entry(struct strbuf *buf, unsigned int mode,
		const char *path, unsigned int path_len, const
		unsigned char *sha1)
{
	strbuf_addf(buf, "%o %.*s%c", mode, path_len, path, '\0');
	strbuf_add(buf, sha1, 20);
}

static void tree_write_stack_init_subtree(struct tree_write_stack *tws,
		const char *path)
{
	struct tree_write_stack *n;
	assert(!tws->next);
	assert(tws->path[0] == '\0' && tws->path[1] == '\0');
	n = (struct tree_write_stack *)
		xmalloc(sizeof(struct tree_write_stack));
	n->next = NULL;
	strbuf_init(&n->buf, 256 * (32 + 40)); /* assume 256 entries per tree */
	n->path[0] = n->path[1] = '\0';
	tws->next = n;
	tws->path[0] = path[0];
	tws->path[1] = path[1];
}

static int tree_write_stack_finish_subtree(struct tree_write_stack *tws)
{
	int ret;
	struct tree_write_stack *n = tws->next;
	unsigned char s[20];
	if (n) {
		ret = tree_write_stack_finish_subtree(n);
		if (ret)
			return ret;
		ret = write_sha1_file(n->buf.buf, n->buf.len, tree_type, s);
		if (ret)
			return ret;
		strbuf_release(&n->buf);
		free(n);
		tws->next = NULL;
		write_tree_entry(&tws->buf, 040000, tws->path, 2, s);
		tws->path[0] = tws->path[1] = '\0';
	}
	return 0;
}

static int write_each_note_helper(struct tree_write_stack *tws,
		const char *path, unsigned int mode,
		const unsigned char *sha1)
{
	size_t path_len = strlen(path);
	unsigned int n = 0;
	int ret;

	/* Determine common part of tree write stack */
	while (tws && 3 * n < path_len &&
	       matches_tree_write_stack(tws, path + 3 * n)) {
		n++;
		tws = tws->next;
	}

	/* tws point to last matching tree_write_stack entry */
	ret = tree_write_stack_finish_subtree(tws);
	if (ret)
		return ret;

	/* Start subtrees needed to satisfy path */
	while (3 * n + 2 < path_len && path[3 * n + 2] == '/') {
		tree_write_stack_init_subtree(tws, path + 3 * n);
		n++;
		tws = tws->next;
	}

	/* There should be no more directory components in the given path */
	assert(memchr(path + 3 * n, '/', path_len - (3 * n)) == NULL);

	/* Finally add given entry to the current tree object */
	write_tree_entry(&tws->buf, mode, path + 3 * n, path_len - (3 * n),
			 sha1);

	return 0;
}

struct write_each_note_data {
	struct tree_write_stack *root;
	struct non_note *next_non_note;
};

static int write_each_non_note_until(const char *note_path,
		struct write_each_note_data *d)
{
	struct non_note *n = d->next_non_note;
	int cmp = 0, ret;
	while (n && (!note_path || (cmp = strcmp(n->path, note_path)) <= 0)) {
		if (note_path && cmp == 0)
			; /* do nothing, prefer note to non-note */
		else {
			ret = write_each_note_helper(d->root, n->path, n->mode,
						     n->sha1);
			if (ret)
				return ret;
		}
		n = n->next;
	}
	d->next_non_note = n;
	return 0;
}

static int write_each_note(const unsigned char *object_sha1,
		const unsigned char *note_sha1, char *note_path,
		void *cb_data)
{
	struct write_each_note_data *d =
		(struct write_each_note_data *) cb_data;
	size_t note_path_len = strlen(note_path);
	unsigned int mode = 0100644;

	if (note_path[note_path_len - 1] == '/') {
		/* subtree entry */
		note_path_len--;
		note_path[note_path_len] = '\0';
		mode = 040000;
	}
	assert(note_path_len <= 40 + 19);

	/* Weave non-note entries into note entries */
	return  write_each_non_note_until(note_path, d) ||
		write_each_note_helper(d->root, note_path, mode, note_sha1);
}

struct note_delete_list {
	struct note_delete_list *next;
	const unsigned char *sha1;
};

static int prune_notes_helper(const unsigned char *object_sha1,
		const unsigned char *note_sha1, char *note_path,
		void *cb_data)
{
	struct note_delete_list **l = (struct note_delete_list **) cb_data;
	struct note_delete_list *n;

	if (has_sha1_file(object_sha1))
		return 0; /* nothing to do for this note */

	/* failed to find object => prune this note */
	n = (struct note_delete_list *) xmalloc(sizeof(*n));
	n->next = *l;
	n->sha1 = object_sha1;
	*l = n;
	return 0;
}

int combine_notes_concatenate(unsigned char *cur_sha1,
		const unsigned char *new_sha1)
{
	char *cur_msg = NULL, *new_msg = NULL, *buf;
	unsigned long cur_len, new_len, buf_len;
	enum object_type cur_type, new_type;
	int ret;

	/* read in both note blob objects */
	if (!is_null_sha1(new_sha1))
		new_msg = read_sha1_file(new_sha1, &new_type, &new_len);
	if (!new_msg || !new_len || new_type != OBJ_BLOB) {
		free(new_msg);
		return 0;
	}
	if (!is_null_sha1(cur_sha1))
		cur_msg = read_sha1_file(cur_sha1, &cur_type, &cur_len);
	if (!cur_msg || !cur_len || cur_type != OBJ_BLOB) {
		free(cur_msg);
		free(new_msg);
		hashcpy(cur_sha1, new_sha1);
		return 0;
	}

	/* we will separate the notes by two newlines anyway */
	if (cur_msg[cur_len - 1] == '\n')
		cur_len--;

	/* concatenate cur_msg and new_msg into buf */
	buf_len = cur_len + 2 + new_len;
	buf = (char *) xmalloc(buf_len);
	memcpy(buf, cur_msg, cur_len);
	buf[cur_len] = '\n';
	buf[cur_len + 1] = '\n';
	memcpy(buf + cur_len + 2, new_msg, new_len);
	free(cur_msg);
	free(new_msg);

	/* create a new blob object from buf */
	ret = write_sha1_file(buf, buf_len, blob_type, cur_sha1);
	free(buf);
	return ret;
}

int combine_notes_overwrite(unsigned char *cur_sha1,
		const unsigned char *new_sha1)
{
	hashcpy(cur_sha1, new_sha1);
	return 0;
}

int combine_notes_ignore(unsigned char *cur_sha1,
		const unsigned char *new_sha1)
{
	return 0;
}

static int string_list_add_note_lines(struct string_list *sort_uniq_list,
				      const unsigned char *sha1)
{
	char *data;
	unsigned long len;
	enum object_type t;
	struct strbuf buf = STRBUF_INIT;
	struct strbuf **lines = NULL;
	int i, list_index;

	if (is_null_sha1(sha1))
		return 0;

	/* read_sha1_file NUL-terminates */
	data = read_sha1_file(sha1, &t, &len);
	if (t != OBJ_BLOB || !data || !len) {
		free(data);
		return t != OBJ_BLOB || !data;
	}

	strbuf_attach(&buf, data, len, len + 1);
	lines = strbuf_split(&buf, '\n');

	for (i = 0; lines[i]; i++) {
		if (lines[i]->buf[lines[i]->len - 1] == '\n')
			strbuf_setlen(lines[i], lines[i]->len - 1);
		if (!lines[i]->len)
			continue; /* skip empty lines */
		list_index = string_list_find_insert_index(sort_uniq_list,
							   lines[i]->buf, 0);
		if (list_index < 0)
			continue; /* skip duplicate lines */
		string_list_insert_at_index(sort_uniq_list, list_index,
					    lines[i]->buf);
	}

	strbuf_list_free(lines);
	strbuf_release(&buf);
	return 0;
}

static int string_list_join_lines_helper(struct string_list_item *item,
					 void *cb_data)
{
	struct strbuf *buf = cb_data;
	strbuf_addstr(buf, item->string);
	strbuf_addch(buf, '\n');
	return 0;
}

int combine_notes_cat_sort_uniq(unsigned char *cur_sha1,
		const unsigned char *new_sha1)
{
	struct string_list sort_uniq_list = { NULL, 0, 0, 1 };
	struct strbuf buf = STRBUF_INIT;
	int ret = 1;

	/* read both note blob objects into unique_lines */
	if (string_list_add_note_lines(&sort_uniq_list, cur_sha1))
		goto out;
	if (string_list_add_note_lines(&sort_uniq_list, new_sha1))
		goto out;

	/* create a new blob object from sort_uniq_list */
	if (for_each_string_list(&sort_uniq_list,
				 string_list_join_lines_helper, &buf))
		goto out;

	ret = write_sha1_file(buf.buf, buf.len, blob_type, cur_sha1);

out:
	strbuf_release(&buf);
	string_list_clear(&sort_uniq_list, 0);
	return ret;
}

static int string_list_add_one_ref(const char *path, const unsigned char *sha1,
				   int flag, void *cb)
{
	struct string_list *refs = cb;
	if (!unsorted_string_list_has_string(refs, path))
		string_list_append(refs, path);
	return 0;
}

void string_list_add_refs_by_glob(struct string_list *list, const char *glob)
{
	if (has_glob_specials(glob)) {
		for_each_glob_ref(string_list_add_one_ref, glob, list);
	} else {
		unsigned char sha1[20];
		if (get_sha1(glob, sha1))
			warning("notes ref %s is invalid", glob);
		if (!unsorted_string_list_has_string(list, glob))
			string_list_append(list, glob);
	}
}

void string_list_add_refs_from_colon_sep(struct string_list *list,
					 const char *globs)
{
	struct strbuf globbuf = STRBUF_INIT;
	struct strbuf **split;
	int i;

	strbuf_addstr(&globbuf, globs);
	split = strbuf_split(&globbuf, ':');

	for (i = 0; split[i]; i++) {
		if (!split[i]->len)
			continue;
		if (split[i]->buf[split[i]->len-1] == ':')
			strbuf_setlen(split[i], split[i]->len-1);
		string_list_add_refs_by_glob(list, split[i]->buf);
	}

	strbuf_list_free(split);
	strbuf_release(&globbuf);
}

static int notes_display_config(const char *k, const char *v, void *cb)
{
	int *load_refs = cb;

	if (*load_refs && !strcmp(k, "notes.displayref")) {
		if (!v)
			config_error_nonbool(k);
		string_list_add_refs_by_glob(&display_notes_refs, v);
	}

	return 0;
}

const char *default_notes_ref(void)
{
	const char *notes_ref = NULL;
	if (!notes_ref)
		notes_ref = getenv(GIT_NOTES_REF_ENVIRONMENT);
	if (!notes_ref)
		notes_ref = notes_ref_name; /* value of core.notesRef config */
	if (!notes_ref)
		notes_ref = GIT_NOTES_DEFAULT_REF;
	return notes_ref;
}

void init_notes(struct notes_tree *t, const char *notes_ref,
		combine_notes_fn combine_notes, int flags)
{
	unsigned char sha1[20], object_sha1[20];
	unsigned mode;
	struct leaf_node root_tree;

	if (!t)
		t = &default_notes_tree;
	assert(!t->initialized);

	if (!notes_ref)
		notes_ref = default_notes_ref();

	if (!combine_notes)
		combine_notes = combine_notes_concatenate;

	t->root = (struct int_node *) xcalloc(sizeof(struct int_node), 1);
	t->first_non_note = NULL;
	t->prev_non_note = NULL;
	t->ref = notes_ref ? xstrdup(notes_ref) : NULL;
	t->combine_notes = combine_notes;
	t->initialized = 1;
	t->dirty = 0;

	if (flags & NOTES_INIT_EMPTY || !notes_ref ||
	    read_ref(notes_ref, object_sha1))
		return;
	if (get_tree_entry(object_sha1, "", sha1, &mode))
		die("Failed to read notes tree referenced by %s (%s)",
		    notes_ref, sha1_to_hex(object_sha1));

	hashclr(root_tree.key_sha1);
	hashcpy(root_tree.val_sha1, sha1);
	load_subtree(t, &root_tree, t->root, 0);
}

struct notes_tree **load_notes_trees(struct string_list *refs)
{
	struct string_list_item *item;
	int counter = 0;
	struct notes_tree **trees;
	trees = xmalloc((refs->nr+1) * sizeof(struct notes_tree *));
	for_each_string_list_item(item, refs) {
		struct notes_tree *t = xcalloc(1, sizeof(struct notes_tree));
		init_notes(t, item->string, combine_notes_ignore, 0);
		trees[counter++] = t;
	}
	trees[counter] = NULL;
	return trees;
}

void init_display_notes(struct display_notes_opt *opt)
{
	char *display_ref_env;
	int load_config_refs = 0;
	display_notes_refs.strdup_strings = 1;

	assert(!display_notes_trees);

	if (!opt || !opt->suppress_default_notes) {
		string_list_append(&display_notes_refs, default_notes_ref());
		display_ref_env = getenv(GIT_NOTES_DISPLAY_REF_ENVIRONMENT);
		if (display_ref_env) {
			string_list_add_refs_from_colon_sep(&display_notes_refs,
							    display_ref_env);
			load_config_refs = 0;
		} else
			load_config_refs = 1;
	}

	git_config(notes_display_config, &load_config_refs);

	if (opt && opt->extra_notes_refs) {
		struct string_list_item *item;
		for_each_string_list_item(item, opt->extra_notes_refs)
			string_list_add_refs_by_glob(&display_notes_refs,
						     item->string);
	}

	display_notes_trees = load_notes_trees(&display_notes_refs);
	string_list_clear(&display_notes_refs, 0);
}

int add_note(struct notes_tree *t, const unsigned char *object_sha1,
		const unsigned char *note_sha1, combine_notes_fn combine_notes)
{
	struct leaf_node *l;

	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);
	t->dirty = 1;
	if (!combine_notes)
		combine_notes = t->combine_notes;
	l = (struct leaf_node *) xmalloc(sizeof(struct leaf_node));
	hashcpy(l->key_sha1, object_sha1);
	hashcpy(l->val_sha1, note_sha1);
	return note_tree_insert(t, t->root, 0, l, PTR_TYPE_NOTE, combine_notes);
}

int remove_note(struct notes_tree *t, const unsigned char *object_sha1)
{
	struct leaf_node l;

	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);
	hashcpy(l.key_sha1, object_sha1);
	hashclr(l.val_sha1);
	note_tree_remove(t, t->root, 0, &l);
	if (is_null_sha1(l.val_sha1)) // no note was removed
		return 1;
	t->dirty = 1;
	return 0;
}

const unsigned char *get_note(struct notes_tree *t,
		const unsigned char *object_sha1)
{
	struct leaf_node *found;

	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);
	found = note_tree_find(t, t->root, 0, object_sha1);
	return found ? found->val_sha1 : NULL;
}

int for_each_note(struct notes_tree *t, int flags, each_note_fn fn,
		void *cb_data)
{
	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);
	return for_each_note_helper(t, t->root, 0, 0, flags, fn, cb_data);
}

int write_notes_tree(struct notes_tree *t, unsigned char *result)
{
	struct tree_write_stack root;
	struct write_each_note_data cb_data;
	int ret;

	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);

	/* Prepare for traversal of current notes tree */
	root.next = NULL; /* last forward entry in list is grounded */
	strbuf_init(&root.buf, 256 * (32 + 40)); /* assume 256 entries */
	root.path[0] = root.path[1] = '\0';
	cb_data.root = &root;
	cb_data.next_non_note = t->first_non_note;

	/* Write tree objects representing current notes tree */
	ret = for_each_note(t, FOR_EACH_NOTE_DONT_UNPACK_SUBTREES |
				FOR_EACH_NOTE_YIELD_SUBTREES,
			write_each_note, &cb_data) ||
		write_each_non_note_until(NULL, &cb_data) ||
		tree_write_stack_finish_subtree(&root) ||
		write_sha1_file(root.buf.buf, root.buf.len, tree_type, result);
	strbuf_release(&root.buf);
	return ret;
}

void prune_notes(struct notes_tree *t, int flags)
{
	struct note_delete_list *l = NULL;

	if (!t)
		t = &default_notes_tree;
	assert(t->initialized);

	for_each_note(t, 0, prune_notes_helper, &l);

	while (l) {
		if (flags & NOTES_PRUNE_VERBOSE)
			printf("%s\n", sha1_to_hex(l->sha1));
		if (!(flags & NOTES_PRUNE_DRYRUN))
			remove_note(t, l->sha1);
		l = l->next;
	}
}

void free_notes(struct notes_tree *t)
{
	if (!t)
		t = &default_notes_tree;
	if (t->root)
		note_tree_free(t->root);
	free(t->root);
	while (t->first_non_note) {
		t->prev_non_note = t->first_non_note->next;
		free(t->first_non_note->path);
		free(t->first_non_note);
		t->first_non_note = t->prev_non_note;
	}
	free(t->ref);
	memset(t, 0, sizeof(struct notes_tree));
}

void format_note(struct notes_tree *t, const unsigned char *object_sha1,
		struct strbuf *sb, const char *output_encoding, int flags)
{
	static const char utf8[] = "utf-8";
	const unsigned char *sha1;
	char *msg, *msg_p;
	unsigned long linelen, msglen;
	enum object_type type;

	if (!t)
		t = &default_notes_tree;
	if (!t->initialized)
		init_notes(t, NULL, NULL, 0);

	sha1 = get_note(t, object_sha1);
	if (!sha1)
		return;

	if (!(msg = read_sha1_file(sha1, &type, &msglen)) || !msglen ||
			type != OBJ_BLOB) {
		free(msg);
		return;
	}

	if (output_encoding && *output_encoding &&
			strcmp(utf8, output_encoding)) {
		char *reencoded = reencode_string(msg, output_encoding, utf8);
		if (reencoded) {
			free(msg);
			msg = reencoded;
			msglen = strlen(msg);
		}
	}

	/* we will end the annotation by a newline anyway */
	if (msglen && msg[msglen - 1] == '\n')
		msglen--;

	if (flags & NOTES_SHOW_HEADER) {
		const char *ref = t->ref;
		if (!ref || !strcmp(ref, GIT_NOTES_DEFAULT_REF)) {
			strbuf_addstr(sb, "\nNotes:\n");
		} else {
			if (!prefixcmp(ref, "refs/"))
				ref += 5;
			if (!prefixcmp(ref, "notes/"))
				ref += 6;
			strbuf_addf(sb, "\nNotes (%s):\n", ref);
		}
	}

	for (msg_p = msg; msg_p < msg + msglen; msg_p += linelen + 1) {
		linelen = strchrnul(msg_p, '\n') - msg_p;

		if (flags & NOTES_INDENT)
			strbuf_addstr(sb, "    ");
		strbuf_add(sb, msg_p, linelen);
		strbuf_addch(sb, '\n');
	}

	free(msg);
}

void format_display_notes(const unsigned char *object_sha1,
			  struct strbuf *sb, const char *output_encoding, int flags)
{
	int i;
	assert(display_notes_trees);
	for (i = 0; display_notes_trees[i]; i++)
		format_note(display_notes_trees[i], object_sha1, sb,
			    output_encoding, flags);
}

int copy_note(struct notes_tree *t,
	      const unsigned char *from_obj, const unsigned char *to_obj,
	      int force, combine_notes_fn combine_notes)
{
	const unsigned char *note = get_note(t, from_obj);
	const unsigned char *existing_note = get_note(t, to_obj);

	if (!force && existing_note)
		return 1;

	if (note)
		return add_note(t, to_obj, note, combine_notes);
	else if (existing_note)
		return add_note(t, to_obj, null_sha1, combine_notes);

	return 0;
}
