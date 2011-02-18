#include "cache.h"
#include "tree.h"
#include "tree-walk.h"

static int score_missing(unsigned mode, const char *path)
{
	int score;

	if (S_ISDIR(mode))
		score = -1000;
	else if (S_ISLNK(mode))
		score = -500;
	else
		score = -50;
	return score;
}

static int score_differs(unsigned mode1, unsigned mode2, const char *path)
{
	int score;

	if (S_ISDIR(mode1) != S_ISDIR(mode2))
		score = -100;
	else if (S_ISLNK(mode1) != S_ISLNK(mode2))
		score = -50;
	else
		score = -5;
	return score;
}

static int score_matches(unsigned mode1, unsigned mode2, const char *path)
{
	int score;

	/* Heh, we found SHA-1 collisions between different kind of objects */
	if (S_ISDIR(mode1) != S_ISDIR(mode2))
		score = -100;
	else if (S_ISLNK(mode1) != S_ISLNK(mode2))
		score = -50;

	else if (S_ISDIR(mode1))
		score = 1000;
	else if (S_ISLNK(mode1))
		score = 500;
	else
		score = 250;
	return score;
}

/*
 * Inspect two trees, and give a score that tells how similar they are.
 */
static int score_trees(const unsigned char *hash1, const unsigned char *hash2)
{
	struct tree_desc one;
	struct tree_desc two;
	void *one_buf, *two_buf;
	int score = 0;
	enum object_type type;
	unsigned long size;

	one_buf = read_sha1_file(hash1, &type, &size);
	if (!one_buf)
		die("unable to read tree (%s)", sha1_to_hex(hash1));
	if (type != OBJ_TREE)
		die("%s is not a tree", sha1_to_hex(hash1));
	init_tree_desc(&one, one_buf, size);
	two_buf = read_sha1_file(hash2, &type, &size);
	if (!two_buf)
		die("unable to read tree (%s)", sha1_to_hex(hash2));
	if (type != OBJ_TREE)
		die("%s is not a tree", sha1_to_hex(hash2));
	init_tree_desc(&two, two_buf, size);
	while (one.size | two.size) {
		const unsigned char *elem1 = elem1;
		const unsigned char *elem2 = elem2;
		const char *path1 = path1;
		const char *path2 = path2;
		unsigned mode1 = mode1;
		unsigned mode2 = mode2;
		int cmp;

		if (one.size)
			elem1 = tree_entry_extract(&one, &path1, &mode1);
		if (two.size)
			elem2 = tree_entry_extract(&two, &path2, &mode2);

		if (!one.size) {
			/* two has more entries */
			score += score_missing(mode2, path2);
			update_tree_entry(&two);
			continue;
		}
		if (!two.size) {
			/* two lacks this entry */
			score += score_missing(mode1, path1);
			update_tree_entry(&one);
			continue;
		}
		cmp = base_name_compare(path1, strlen(path1), mode1,
					path2, strlen(path2), mode2);
		if (cmp < 0) {
			/* path1 does not appear in two */
			score += score_missing(mode1, path1);
			update_tree_entry(&one);
			continue;
		}
		else if (cmp > 0) {
			/* path2 does not appear in one */
			score += score_missing(mode2, path2);
			update_tree_entry(&two);
			continue;
		}
		else if (hashcmp(elem1, elem2))
			/* they are different */
			score += score_differs(mode1, mode2, path1);
		else
			/* same subtree or blob */
			score += score_matches(mode1, mode2, path1);
		update_tree_entry(&one);
		update_tree_entry(&two);
	}
	free(one_buf);
	free(two_buf);
	return score;
}

/*
 * Match one itself and its subtrees with two and pick the best match.
 */
static void match_trees(const unsigned char *hash1,
			const unsigned char *hash2,
			int *best_score,
			char **best_match,
			const char *base,
			int recurse_limit)
{
	struct tree_desc one;
	void *one_buf;
	enum object_type type;
	unsigned long size;

	one_buf = read_sha1_file(hash1, &type, &size);
	if (!one_buf)
		die("unable to read tree (%s)", sha1_to_hex(hash1));
	if (type != OBJ_TREE)
		die("%s is not a tree", sha1_to_hex(hash1));
	init_tree_desc(&one, one_buf, size);

	while (one.size) {
		const char *path;
		const unsigned char *elem;
		unsigned mode;
		int score;

		elem = tree_entry_extract(&one, &path, &mode);
		if (!S_ISDIR(mode))
			goto next;
		score = score_trees(elem, hash2);
		if (*best_score < score) {
			char *newpath;
			newpath = xmalloc(strlen(base) + strlen(path) + 1);
			sprintf(newpath, "%s%s", base, path);
			free(*best_match);
			*best_match = newpath;
			*best_score = score;
		}
		if (recurse_limit) {
			char *newbase;
			newbase = xmalloc(strlen(base) + strlen(path) + 2);
			sprintf(newbase, "%s%s/", base, path);
			match_trees(elem, hash2, best_score, best_match,
				    newbase, recurse_limit - 1);
			free(newbase);
		}

	next:
		update_tree_entry(&one);
	}
	free(one_buf);
}

/*
 * A tree "hash1" has a subdirectory at "prefix".  Come up with a
 * tree object by replacing it with another tree "hash2".
 */
static int splice_tree(const unsigned char *hash1,
		       const char *prefix,
		       const unsigned char *hash2,
		       unsigned char *result)
{
	char *subpath;
	int toplen;
	char *buf;
	unsigned long sz;
	struct tree_desc desc;
	unsigned char *rewrite_here;
	const unsigned char *rewrite_with;
	unsigned char subtree[20];
	enum object_type type;
	int status;

	subpath = strchr(prefix, '/');
	if (!subpath)
		toplen = strlen(prefix);
	else {
		toplen = subpath - prefix;
		subpath++;
	}

	buf = read_sha1_file(hash1, &type, &sz);
	if (!buf)
		die("cannot read tree %s", sha1_to_hex(hash1));
	init_tree_desc(&desc, buf, sz);

	rewrite_here = NULL;
	while (desc.size) {
		const char *name;
		unsigned mode;
		const unsigned char *sha1;

		sha1 = tree_entry_extract(&desc, &name, &mode);
		if (strlen(name) == toplen &&
		    !memcmp(name, prefix, toplen)) {
			if (!S_ISDIR(mode))
				die("entry %s in tree %s is not a tree",
				    name, sha1_to_hex(hash1));
			rewrite_here = (unsigned char *) sha1;
			break;
		}
		update_tree_entry(&desc);
	}
	if (!rewrite_here)
		die("entry %.*s not found in tree %s",
		    toplen, prefix, sha1_to_hex(hash1));
	if (subpath) {
		status = splice_tree(rewrite_here, subpath, hash2, subtree);
		if (status)
			return status;
		rewrite_with = subtree;
	}
	else
		rewrite_with = hash2;
	hashcpy(rewrite_here, rewrite_with);
	status = write_sha1_file(buf, sz, tree_type, result);
	free(buf);
	return status;
}

/*
 * We are trying to come up with a merge between one and two that
 * results in a tree shape similar to one.  The tree two might
 * correspond to a subtree of one, in which case it needs to be
 * shifted down by prefixing otherwise empty directories.  On the
 * other hand, it could cover tree one and we might need to pick a
 * subtree of it.
 */
void shift_tree(const unsigned char *hash1,
		const unsigned char *hash2,
		unsigned char *shifted,
		int depth_limit)
{
	char *add_prefix;
	char *del_prefix;
	int add_score, del_score;

	/*
	 * NEEDSWORK: this limits the recursion depth to hardcoded
	 * value '2' to avoid excessive overhead.
	 */
	if (!depth_limit)
		depth_limit = 2;

	add_score = del_score = score_trees(hash1, hash2);
	add_prefix = xcalloc(1, 1);
	del_prefix = xcalloc(1, 1);

	/*
	 * See if one's subtree resembles two; if so we need to prefix
	 * two with a few fake trees to match the prefix.
	 */
	match_trees(hash1, hash2, &add_score, &add_prefix, "", depth_limit);

	/*
	 * See if two's subtree resembles one; if so we need to
	 * pick only subtree of two.
	 */
	match_trees(hash2, hash1, &del_score, &del_prefix, "", depth_limit);

	/* Assume we do not have to do any shifting */
	hashcpy(shifted, hash2);

	if (add_score < del_score) {
		/* We need to pick a subtree of two */
		unsigned mode;

		if (!*del_prefix)
			return;

		if (get_tree_entry(hash2, del_prefix, shifted, &mode))
			die("cannot find path %s in tree %s",
			    del_prefix, sha1_to_hex(hash2));
		return;
	}

	if (!*add_prefix)
		return;

	splice_tree(hash1, add_prefix, hash2, shifted);
}

/*
 * The user says the trees will be shifted by this much.
 * Unfortunately we cannot fundamentally tell which one to
 * be prefixed, as recursive merge can work in either direction.
 */
void shift_tree_by(const unsigned char *hash1,
		   const unsigned char *hash2,
		   unsigned char *shifted,
		   const char *shift_prefix)
{
	unsigned char sub1[20], sub2[20];
	unsigned mode1, mode2;
	unsigned candidate = 0;

	/* Can hash2 be a tree at shift_prefix in tree hash1? */
	if (!get_tree_entry(hash1, shift_prefix, sub1, &mode1) &&
	    S_ISDIR(mode1))
		candidate |= 1;

	/* Can hash1 be a tree at shift_prefix in tree hash2? */
	if (!get_tree_entry(hash2, shift_prefix, sub2, &mode2) &&
	    S_ISDIR(mode2))
		candidate |= 2;

	if (candidate == 3) {
		/* Both are plausible -- we need to evaluate the score */
		int best_score = score_trees(hash1, hash2);
		int score;

		candidate = 0;
		score = score_trees(sub1, hash2);
		if (score > best_score) {
			candidate = 1;
			best_score = score;
		}
		score = score_trees(sub2, hash1);
		if (score > best_score)
			candidate = 2;
	}

	if (!candidate) {
		/* Neither is plausible -- do not shift */
		hashcpy(shifted, hash2);
		return;
	}

	if (candidate == 1)
		/*
		 * shift tree2 down by adding shift_prefix above it
		 * to match tree1.
		 */
		splice_tree(hash1, shift_prefix, hash2, shifted);
	else
		/*
		 * shift tree2 up by removing shift_prefix from it
		 * to match tree1.
		 */
		hashcpy(shifted, sub2);
}
