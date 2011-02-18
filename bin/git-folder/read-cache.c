/*
 * GIT - The information manager from hell
 *
 * Copyright (C) Linus Torvalds, 2005
 */
#define NO_THE_INDEX_COMPATIBILITY_MACROS
#include "cache.h"
#include "cache-tree.h"
#include "refs.h"
#include "dir.h"
#include "tree.h"
#include "commit.h"
#include "blob.h"
#include "resolve-undo.h"

static struct cache_entry *refresh_cache_entry(struct cache_entry *ce, int really);

/* Index extensions.
 *
 * The first letter should be 'A'..'Z' for extensions that are not
 * necessary for a correct operation (i.e. optimization data).
 * When new extensions are added that _needs_ to be understood in
 * order to correctly interpret the index file, pick character that
 * is outside the range, to cause the reader to abort.
 */

#define CACHE_EXT(s) ( (s[0]<<24)|(s[1]<<16)|(s[2]<<8)|(s[3]) )
#define CACHE_EXT_TREE 0x54524545	/* "TREE" */
#define CACHE_EXT_RESOLVE_UNDO 0x52455543 /* "REUC" */

struct index_state the_index;

static void set_index_entry(struct index_state *istate, int nr, struct cache_entry *ce)
{
	istate->cache[nr] = ce;
	add_name_hash(istate, ce);
}

static void replace_index_entry(struct index_state *istate, int nr, struct cache_entry *ce)
{
	struct cache_entry *old = istate->cache[nr];

	remove_name_hash(old);
	set_index_entry(istate, nr, ce);
	istate->cache_changed = 1;
}

void rename_index_entry_at(struct index_state *istate, int nr, const char *new_name)
{
	struct cache_entry *old = istate->cache[nr], *new;
	int namelen = strlen(new_name);

	new = xmalloc(cache_entry_size(namelen));
	copy_cache_entry(new, old);
	new->ce_flags &= ~(CE_STATE_MASK | CE_NAMEMASK);
	new->ce_flags |= (namelen >= CE_NAMEMASK ? CE_NAMEMASK : namelen);
	memcpy(new->name, new_name, namelen + 1);

	cache_tree_invalidate_path(istate->cache_tree, old->name);
	remove_index_entry_at(istate, nr);
	add_index_entry(istate, new, ADD_CACHE_OK_TO_ADD|ADD_CACHE_OK_TO_REPLACE);
}

/*
 * This only updates the "non-critical" parts of the directory
 * cache, ie the parts that aren't tracked by GIT, and only used
 * to validate the cache.
 */
void fill_stat_cache_info(struct cache_entry *ce, struct stat *st)
{
	ce->ce_ctime.sec = (unsigned int)st->st_ctime;
	ce->ce_mtime.sec = (unsigned int)st->st_mtime;
	ce->ce_ctime.nsec = ST_CTIME_NSEC(*st);
	ce->ce_mtime.nsec = ST_MTIME_NSEC(*st);
	ce->ce_dev = st->st_dev;
	ce->ce_ino = st->st_ino;
	ce->ce_uid = st->st_uid;
	ce->ce_gid = st->st_gid;
	ce->ce_size = st->st_size;

	if (assume_unchanged)
		ce->ce_flags |= CE_VALID;

	if (S_ISREG(st->st_mode))
		ce_mark_uptodate(ce);
}

static int ce_compare_data(struct cache_entry *ce, struct stat *st)
{
	int match = -1;
	int fd = open(ce->name, O_RDONLY);

	if (fd >= 0) {
		unsigned char sha1[20];
		if (!index_fd(sha1, fd, st, 0, OBJ_BLOB, ce->name))
			match = hashcmp(sha1, ce->sha1);
		/* index_fd() closed the file descriptor already */
	}
	return match;
}

static int ce_compare_link(struct cache_entry *ce, size_t expected_size)
{
	int match = -1;
	void *buffer;
	unsigned long size;
	enum object_type type;
	struct strbuf sb = STRBUF_INIT;

	if (strbuf_readlink(&sb, ce->name, expected_size))
		return -1;

	buffer = read_sha1_file(ce->sha1, &type, &size);
	if (buffer) {
		if (size == sb.len)
			match = memcmp(buffer, sb.buf, size);
		free(buffer);
	}
	strbuf_release(&sb);
	return match;
}

static int ce_compare_gitlink(struct cache_entry *ce)
{
	unsigned char sha1[20];

	/*
	 * We don't actually require that the .git directory
	 * under GITLINK directory be a valid git directory. It
	 * might even be missing (in case nobody populated that
	 * sub-project).
	 *
	 * If so, we consider it always to match.
	 */
	if (resolve_gitlink_ref(ce->name, "HEAD", sha1) < 0)
		return 0;
	return hashcmp(sha1, ce->sha1);
}

static int ce_modified_check_fs(struct cache_entry *ce, struct stat *st)
{
	switch (st->st_mode & S_IFMT) {
	case S_IFREG:
		if (ce_compare_data(ce, st))
			return DATA_CHANGED;
		break;
	case S_IFLNK:
		if (ce_compare_link(ce, xsize_t(st->st_size)))
			return DATA_CHANGED;
		break;
	case S_IFDIR:
		if (S_ISGITLINK(ce->ce_mode))
			return ce_compare_gitlink(ce) ? DATA_CHANGED : 0;
	default:
		return TYPE_CHANGED;
	}
	return 0;
}

static int is_empty_blob_sha1(const unsigned char *sha1)
{
	static const unsigned char empty_blob_sha1[20] = {
		0xe6,0x9d,0xe2,0x9b,0xb2,0xd1,0xd6,0x43,0x4b,0x8b,
		0x29,0xae,0x77,0x5a,0xd8,0xc2,0xe4,0x8c,0x53,0x91
	};

	return !hashcmp(sha1, empty_blob_sha1);
}

static int ce_match_stat_basic(struct cache_entry *ce, struct stat *st)
{
	unsigned int changed = 0;

	if (ce->ce_flags & CE_REMOVE)
		return MODE_CHANGED | DATA_CHANGED | TYPE_CHANGED;

	switch (ce->ce_mode & S_IFMT) {
	case S_IFREG:
		changed |= !S_ISREG(st->st_mode) ? TYPE_CHANGED : 0;
		/* We consider only the owner x bit to be relevant for
		 * "mode changes"
		 */
		if (trust_executable_bit &&
		    (0100 & (ce->ce_mode ^ st->st_mode)))
			changed |= MODE_CHANGED;
		break;
	case S_IFLNK:
		if (!S_ISLNK(st->st_mode) &&
		    (has_symlinks || !S_ISREG(st->st_mode)))
			changed |= TYPE_CHANGED;
		break;
	case S_IFGITLINK:
		/* We ignore most of the st_xxx fields for gitlinks */
		if (!S_ISDIR(st->st_mode))
			changed |= TYPE_CHANGED;
		else if (ce_compare_gitlink(ce))
			changed |= DATA_CHANGED;
		return changed;
	default:
		die("internal error: ce_mode is %o", ce->ce_mode);
	}
	if (ce->ce_mtime.sec != (unsigned int)st->st_mtime)
		changed |= MTIME_CHANGED;
	if (trust_ctime && ce->ce_ctime.sec != (unsigned int)st->st_ctime)
		changed |= CTIME_CHANGED;

#ifdef USE_NSEC
	if (ce->ce_mtime.nsec != ST_MTIME_NSEC(*st))
		changed |= MTIME_CHANGED;
	if (trust_ctime && ce->ce_ctime.nsec != ST_CTIME_NSEC(*st))
		changed |= CTIME_CHANGED;
#endif

	if (ce->ce_uid != (unsigned int) st->st_uid ||
	    ce->ce_gid != (unsigned int) st->st_gid)
		changed |= OWNER_CHANGED;
	if (ce->ce_ino != (unsigned int) st->st_ino)
		changed |= INODE_CHANGED;

#ifdef USE_STDEV
	/*
	 * st_dev breaks on network filesystems where different
	 * clients will have different views of what "device"
	 * the filesystem is on
	 */
	if (ce->ce_dev != (unsigned int) st->st_dev)
		changed |= INODE_CHANGED;
#endif

	if (ce->ce_size != (unsigned int) st->st_size)
		changed |= DATA_CHANGED;

	/* Racily smudged entry? */
	if (!ce->ce_size) {
		if (!is_empty_blob_sha1(ce->sha1))
			changed |= DATA_CHANGED;
	}

	return changed;
}

static int is_racy_timestamp(const struct index_state *istate, struct cache_entry *ce)
{
	return (!S_ISGITLINK(ce->ce_mode) &&
		istate->timestamp.sec &&
#ifdef USE_NSEC
		 /* nanosecond timestamped files can also be racy! */
		(istate->timestamp.sec < ce->ce_mtime.sec ||
		 (istate->timestamp.sec == ce->ce_mtime.sec &&
		  istate->timestamp.nsec <= ce->ce_mtime.nsec))
#else
		istate->timestamp.sec <= ce->ce_mtime.sec
#endif
		 );
}

int ie_match_stat(const struct index_state *istate,
		  struct cache_entry *ce, struct stat *st,
		  unsigned int options)
{
	unsigned int changed;
	int ignore_valid = options & CE_MATCH_IGNORE_VALID;
	int ignore_skip_worktree = options & CE_MATCH_IGNORE_SKIP_WORKTREE;
	int assume_racy_is_modified = options & CE_MATCH_RACY_IS_DIRTY;

	/*
	 * If it's marked as always valid in the index, it's
	 * valid whatever the checked-out copy says.
	 *
	 * skip-worktree has the same effect with higher precedence
	 */
	if (!ignore_skip_worktree && ce_skip_worktree(ce))
		return 0;
	if (!ignore_valid && (ce->ce_flags & CE_VALID))
		return 0;

	/*
	 * Intent-to-add entries have not been added, so the index entry
	 * by definition never matches what is in the work tree until it
	 * actually gets added.
	 */
	if (ce->ce_flags & CE_INTENT_TO_ADD)
		return DATA_CHANGED | TYPE_CHANGED | MODE_CHANGED;

	changed = ce_match_stat_basic(ce, st);

	/*
	 * Within 1 second of this sequence:
	 * 	echo xyzzy >file && git-update-index --add file
	 * running this command:
	 * 	echo frotz >file
	 * would give a falsely clean cache entry.  The mtime and
	 * length match the cache, and other stat fields do not change.
	 *
	 * We could detect this at update-index time (the cache entry
	 * being registered/updated records the same time as "now")
	 * and delay the return from git-update-index, but that would
	 * effectively mean we can make at most one commit per second,
	 * which is not acceptable.  Instead, we check cache entries
	 * whose mtime are the same as the index file timestamp more
	 * carefully than others.
	 */
	if (!changed && is_racy_timestamp(istate, ce)) {
		if (assume_racy_is_modified)
			changed |= DATA_CHANGED;
		else
			changed |= ce_modified_check_fs(ce, st);
	}

	return changed;
}

int ie_modified(const struct index_state *istate,
		struct cache_entry *ce, struct stat *st, unsigned int options)
{
	int changed, changed_fs;

	changed = ie_match_stat(istate, ce, st, options);
	if (!changed)
		return 0;
	/*
	 * If the mode or type has changed, there's no point in trying
	 * to refresh the entry - it's not going to match
	 */
	if (changed & (MODE_CHANGED | TYPE_CHANGED))
		return changed;

	/*
	 * Immediately after read-tree or update-index --cacheinfo,
	 * the length field is zero, as we have never even read the
	 * lstat(2) information once, and we cannot trust DATA_CHANGED
	 * returned by ie_match_stat() which in turn was returned by
	 * ce_match_stat_basic() to signal that the filesize of the
	 * blob changed.  We have to actually go to the filesystem to
	 * see if the contents match, and if so, should answer "unchanged".
	 *
	 * The logic does not apply to gitlinks, as ce_match_stat_basic()
	 * already has checked the actual HEAD from the filesystem in the
	 * subproject.  If ie_match_stat() already said it is different,
	 * then we know it is.
	 */
	if ((changed & DATA_CHANGED) &&
	    (S_ISGITLINK(ce->ce_mode) || ce->ce_size != 0))
		return changed;

	changed_fs = ce_modified_check_fs(ce, st);
	if (changed_fs)
		return changed | changed_fs;
	return 0;
}

int base_name_compare(const char *name1, int len1, int mode1,
		      const char *name2, int len2, int mode2)
{
	unsigned char c1, c2;
	int len = len1 < len2 ? len1 : len2;
	int cmp;

	cmp = memcmp(name1, name2, len);
	if (cmp)
		return cmp;
	c1 = name1[len];
	c2 = name2[len];
	if (!c1 && S_ISDIR(mode1))
		c1 = '/';
	if (!c2 && S_ISDIR(mode2))
		c2 = '/';
	return (c1 < c2) ? -1 : (c1 > c2) ? 1 : 0;
}

/*
 * df_name_compare() is identical to base_name_compare(), except it
 * compares conflicting directory/file entries as equal. Note that
 * while a directory name compares as equal to a regular file, they
 * then individually compare _differently_ to a filename that has
 * a dot after the basename (because '\0' < '.' < '/').
 *
 * This is used by routines that want to traverse the git namespace
 * but then handle conflicting entries together when possible.
 */
int df_name_compare(const char *name1, int len1, int mode1,
		    const char *name2, int len2, int mode2)
{
	int len = len1 < len2 ? len1 : len2, cmp;
	unsigned char c1, c2;

	cmp = memcmp(name1, name2, len);
	if (cmp)
		return cmp;
	/* Directories and files compare equal (same length, same name) */
	if (len1 == len2)
		return 0;
	c1 = name1[len];
	if (!c1 && S_ISDIR(mode1))
		c1 = '/';
	c2 = name2[len];
	if (!c2 && S_ISDIR(mode2))
		c2 = '/';
	if (c1 == '/' && !c2)
		return 0;
	if (c2 == '/' && !c1)
		return 0;
	return c1 - c2;
}

int cache_name_compare(const char *name1, int flags1, const char *name2, int flags2)
{
	int len1 = flags1 & CE_NAMEMASK;
	int len2 = flags2 & CE_NAMEMASK;
	int len = len1 < len2 ? len1 : len2;
	int cmp;

	cmp = memcmp(name1, name2, len);
	if (cmp)
		return cmp;
	if (len1 < len2)
		return -1;
	if (len1 > len2)
		return 1;

	/* Compare stages  */
	flags1 &= CE_STAGEMASK;
	flags2 &= CE_STAGEMASK;

	if (flags1 < flags2)
		return -1;
	if (flags1 > flags2)
		return 1;
	return 0;
}

int index_name_pos(const struct index_state *istate, const char *name, int namelen)
{
	int first, last;

	first = 0;
	last = istate->cache_nr;
	while (last > first) {
		int next = (last + first) >> 1;
		struct cache_entry *ce = istate->cache[next];
		int cmp = cache_name_compare(name, namelen, ce->name, ce->ce_flags);
		if (!cmp)
			return next;
		if (cmp < 0) {
			last = next;
			continue;
		}
		first = next+1;
	}
	return -first-1;
}

/* Remove entry, return true if there are more entries to go.. */
int remove_index_entry_at(struct index_state *istate, int pos)
{
	struct cache_entry *ce = istate->cache[pos];

	record_resolve_undo(istate, ce);
	remove_name_hash(ce);
	istate->cache_changed = 1;
	istate->cache_nr--;
	if (pos >= istate->cache_nr)
		return 0;
	memmove(istate->cache + pos,
		istate->cache + pos + 1,
		(istate->cache_nr - pos) * sizeof(struct cache_entry *));
	return 1;
}

/*
 * Remove all cache ententries marked for removal, that is where
 * CE_REMOVE is set in ce_flags.  This is much more effective than
 * calling remove_index_entry_at() for each entry to be removed.
 */
void remove_marked_cache_entries(struct index_state *istate)
{
	struct cache_entry **ce_array = istate->cache;
	unsigned int i, j;

	for (i = j = 0; i < istate->cache_nr; i++) {
		if (ce_array[i]->ce_flags & CE_REMOVE)
			remove_name_hash(ce_array[i]);
		else
			ce_array[j++] = ce_array[i];
	}
	istate->cache_changed = 1;
	istate->cache_nr = j;
}

int remove_file_from_index(struct index_state *istate, const char *path)
{
	int pos = index_name_pos(istate, path, strlen(path));
	if (pos < 0)
		pos = -pos-1;
	cache_tree_invalidate_path(istate->cache_tree, path);
	while (pos < istate->cache_nr && !strcmp(istate->cache[pos]->name, path))
		remove_index_entry_at(istate, pos);
	return 0;
}

static int compare_name(struct cache_entry *ce, const char *path, int namelen)
{
	return namelen != ce_namelen(ce) || memcmp(path, ce->name, namelen);
}

static int index_name_pos_also_unmerged(struct index_state *istate,
	const char *path, int namelen)
{
	int pos = index_name_pos(istate, path, namelen);
	struct cache_entry *ce;

	if (pos >= 0)
		return pos;

	/* maybe unmerged? */
	pos = -1 - pos;
	if (pos >= istate->cache_nr ||
			compare_name((ce = istate->cache[pos]), path, namelen))
		return -1;

	/* order of preference: stage 2, 1, 3 */
	if (ce_stage(ce) == 1 && pos + 1 < istate->cache_nr &&
			ce_stage((ce = istate->cache[pos + 1])) == 2 &&
			!compare_name(ce, path, namelen))
		pos++;
	return pos;
}

static int different_name(struct cache_entry *ce, struct cache_entry *alias)
{
	int len = ce_namelen(ce);
	return ce_namelen(alias) != len || memcmp(ce->name, alias->name, len);
}

/*
 * If we add a filename that aliases in the cache, we will use the
 * name that we already have - but we don't want to update the same
 * alias twice, because that implies that there were actually two
 * different files with aliasing names!
 *
 * So we use the CE_ADDED flag to verify that the alias was an old
 * one before we accept it as
 */
static struct cache_entry *create_alias_ce(struct cache_entry *ce, struct cache_entry *alias)
{
	int len;
	struct cache_entry *new;

	if (alias->ce_flags & CE_ADDED)
		die("Will not add file alias '%s' ('%s' already exists in index)", ce->name, alias->name);

	/* Ok, create the new entry using the name of the existing alias */
	len = ce_namelen(alias);
	new = xcalloc(1, cache_entry_size(len));
	memcpy(new->name, alias->name, len);
	copy_cache_entry(new, ce);
	free(ce);
	return new;
}

static void record_intent_to_add(struct cache_entry *ce)
{
	unsigned char sha1[20];
	if (write_sha1_file("", 0, blob_type, sha1))
		die("cannot create an empty blob in the object database");
	hashcpy(ce->sha1, sha1);
}

int add_to_index(struct index_state *istate, const char *path, struct stat *st, int flags)
{
	int size, namelen, was_same;
	mode_t st_mode = st->st_mode;
	struct cache_entry *ce, *alias;
	unsigned ce_option = CE_MATCH_IGNORE_VALID|CE_MATCH_IGNORE_SKIP_WORKTREE|CE_MATCH_RACY_IS_DIRTY;
	int verbose = flags & (ADD_CACHE_VERBOSE | ADD_CACHE_PRETEND);
	int pretend = flags & ADD_CACHE_PRETEND;
	int intent_only = flags & ADD_CACHE_INTENT;
	int add_option = (ADD_CACHE_OK_TO_ADD|ADD_CACHE_OK_TO_REPLACE|
			  (intent_only ? ADD_CACHE_NEW_ONLY : 0));

	if (!S_ISREG(st_mode) && !S_ISLNK(st_mode) && !S_ISDIR(st_mode))
		return error("%s: can only add regular files, symbolic links or git-directories", path);

	namelen = strlen(path);
	if (S_ISDIR(st_mode)) {
		while (namelen && path[namelen-1] == '/')
			namelen--;
	}
	size = cache_entry_size(namelen);
	ce = xcalloc(1, size);
	memcpy(ce->name, path, namelen);
	ce->ce_flags = namelen;
	if (!intent_only)
		fill_stat_cache_info(ce, st);
	else
		ce->ce_flags |= CE_INTENT_TO_ADD;

	if (trust_executable_bit && has_symlinks)
		ce->ce_mode = create_ce_mode(st_mode);
	else {
		/* If there is an existing entry, pick the mode bits and type
		 * from it, otherwise assume unexecutable regular file.
		 */
		struct cache_entry *ent;
		int pos = index_name_pos_also_unmerged(istate, path, namelen);

		ent = (0 <= pos) ? istate->cache[pos] : NULL;
		ce->ce_mode = ce_mode_from_stat(ent, st_mode);
	}

	/* When core.ignorecase=true, determine if a directory of the same name but differing
	 * case already exists within the Git repository.  If it does, ensure the directory
	 * case of the file being added to the repository matches (is folded into) the existing
	 * entry's directory case.
	 */
	if (ignore_case) {
		const char *startPtr = ce->name;
		const char *ptr = startPtr;
		while (*ptr) {
			while (*ptr && *ptr != '/')
				++ptr;
			if (*ptr == '/') {
				struct cache_entry *foundce;
				++ptr;
				foundce = index_name_exists(&the_index, ce->name, ptr - ce->name, ignore_case);
				if (foundce) {
					memcpy((void *)startPtr, foundce->name + (startPtr - ce->name), ptr - startPtr);
					startPtr = ptr;
				}
			}
		}
	}

	alias = index_name_exists(istate, ce->name, ce_namelen(ce), ignore_case);
	if (alias && !ce_stage(alias) && !ie_match_stat(istate, alias, st, ce_option)) {
		/* Nothing changed, really */
		free(ce);
		if (!S_ISGITLINK(alias->ce_mode))
			ce_mark_uptodate(alias);
		alias->ce_flags |= CE_ADDED;
		return 0;
	}
	if (!intent_only) {
		if (index_path(ce->sha1, path, st, 1))
			return error("unable to index file %s", path);
	} else
		record_intent_to_add(ce);

	if (ignore_case && alias && different_name(ce, alias))
		ce = create_alias_ce(ce, alias);
	ce->ce_flags |= CE_ADDED;

	/* It was suspected to be racily clean, but it turns out to be Ok */
	was_same = (alias &&
		    !ce_stage(alias) &&
		    !hashcmp(alias->sha1, ce->sha1) &&
		    ce->ce_mode == alias->ce_mode);

	if (pretend)
		;
	else if (add_index_entry(istate, ce, add_option))
		return error("unable to add %s to index",path);
	if (verbose && !was_same)
		printf("add '%s'\n", path);
	return 0;
}

int add_file_to_index(struct index_state *istate, const char *path, int flags)
{
	struct stat st;
	if (lstat(path, &st))
		die_errno("unable to stat '%s'", path);
	return add_to_index(istate, path, &st, flags);
}

struct cache_entry *make_cache_entry(unsigned int mode,
		const unsigned char *sha1, const char *path, int stage,
		int refresh)
{
	int size, len;
	struct cache_entry *ce;

	if (!verify_path(path)) {
		error("Invalid path '%s'", path);
		return NULL;
	}

	len = strlen(path);
	size = cache_entry_size(len);
	ce = xcalloc(1, size);

	hashcpy(ce->sha1, sha1);
	memcpy(ce->name, path, len);
	ce->ce_flags = create_ce_flags(len, stage);
	ce->ce_mode = create_ce_mode(mode);

	if (refresh)
		return refresh_cache_entry(ce, 0);

	return ce;
}

int ce_same_name(struct cache_entry *a, struct cache_entry *b)
{
	int len = ce_namelen(a);
	return ce_namelen(b) == len && !memcmp(a->name, b->name, len);
}

int ce_path_match(const struct cache_entry *ce, const char **pathspec)
{
	const char *match, *name;
	int len;

	if (!pathspec)
		return 1;

	len = ce_namelen(ce);
	name = ce->name;
	while ((match = *pathspec++) != NULL) {
		int matchlen = strlen(match);
		if (matchlen > len)
			continue;
		if (memcmp(name, match, matchlen))
			continue;
		if (matchlen && name[matchlen-1] == '/')
			return 1;
		if (name[matchlen] == '/' || !name[matchlen])
			return 1;
		if (!matchlen)
			return 1;
	}
	return 0;
}

/*
 * We fundamentally don't like some paths: we don't want
 * dot or dot-dot anywhere, and for obvious reasons don't
 * want to recurse into ".git" either.
 *
 * Also, we don't want double slashes or slashes at the
 * end that can make pathnames ambiguous.
 */
static int verify_dotfile(const char *rest)
{
	/*
	 * The first character was '.', but that
	 * has already been discarded, we now test
	 * the rest.
	 */
	switch (*rest) {
	/* "." is not allowed */
	case '\0': case '/':
		return 0;

	/*
	 * ".git" followed by  NUL or slash is bad. This
	 * shares the path end test with the ".." case.
	 */
	case 'g':
		if (rest[1] != 'i')
			break;
		if (rest[2] != 't')
			break;
		rest += 2;
	/* fallthrough */
	case '.':
		if (rest[1] == '\0' || rest[1] == '/')
			return 0;
	}
	return 1;
}

int verify_path(const char *path)
{
	char c;

	goto inside;
	for (;;) {
		if (!c)
			return 1;
		if (c == '/') {
inside:
			c = *path++;
			switch (c) {
			default:
				continue;
			case '/': case '\0':
				break;
			case '.':
				if (verify_dotfile(path))
					continue;
			}
			return 0;
		}
		c = *path++;
	}
}

/*
 * Do we have another file that has the beginning components being a
 * proper superset of the name we're trying to add?
 */
static int has_file_name(struct index_state *istate,
			 const struct cache_entry *ce, int pos, int ok_to_replace)
{
	int retval = 0;
	int len = ce_namelen(ce);
	int stage = ce_stage(ce);
	const char *name = ce->name;

	while (pos < istate->cache_nr) {
		struct cache_entry *p = istate->cache[pos++];

		if (len >= ce_namelen(p))
			break;
		if (memcmp(name, p->name, len))
			break;
		if (ce_stage(p) != stage)
			continue;
		if (p->name[len] != '/')
			continue;
		if (p->ce_flags & CE_REMOVE)
			continue;
		retval = -1;
		if (!ok_to_replace)
			break;
		remove_index_entry_at(istate, --pos);
	}
	return retval;
}

/*
 * Do we have another file with a pathname that is a proper
 * subset of the name we're trying to add?
 */
static int has_dir_name(struct index_state *istate,
			const struct cache_entry *ce, int pos, int ok_to_replace)
{
	int retval = 0;
	int stage = ce_stage(ce);
	const char *name = ce->name;
	const char *slash = name + ce_namelen(ce);

	for (;;) {
		int len;

		for (;;) {
			if (*--slash == '/')
				break;
			if (slash <= ce->name)
				return retval;
		}
		len = slash - name;

		pos = index_name_pos(istate, name, create_ce_flags(len, stage));
		if (pos >= 0) {
			/*
			 * Found one, but not so fast.  This could
			 * be a marker that says "I was here, but
			 * I am being removed".  Such an entry is
			 * not a part of the resulting tree, and
			 * it is Ok to have a directory at the same
			 * path.
			 */
			if (!(istate->cache[pos]->ce_flags & CE_REMOVE)) {
				retval = -1;
				if (!ok_to_replace)
					break;
				remove_index_entry_at(istate, pos);
				continue;
			}
		}
		else
			pos = -pos-1;

		/*
		 * Trivial optimization: if we find an entry that
		 * already matches the sub-directory, then we know
		 * we're ok, and we can exit.
		 */
		while (pos < istate->cache_nr) {
			struct cache_entry *p = istate->cache[pos];
			if ((ce_namelen(p) <= len) ||
			    (p->name[len] != '/') ||
			    memcmp(p->name, name, len))
				break; /* not our subdirectory */
			if (ce_stage(p) == stage && !(p->ce_flags & CE_REMOVE))
				/*
				 * p is at the same stage as our entry, and
				 * is a subdirectory of what we are looking
				 * at, so we cannot have conflicts at our
				 * level or anything shorter.
				 */
				return retval;
			pos++;
		}
	}
	return retval;
}

/* We may be in a situation where we already have path/file and path
 * is being added, or we already have path and path/file is being
 * added.  Either one would result in a nonsense tree that has path
 * twice when git-write-tree tries to write it out.  Prevent it.
 *
 * If ok-to-replace is specified, we remove the conflicting entries
 * from the cache so the caller should recompute the insert position.
 * When this happens, we return non-zero.
 */
static int check_file_directory_conflict(struct index_state *istate,
					 const struct cache_entry *ce,
					 int pos, int ok_to_replace)
{
	int retval;

	/*
	 * When ce is an "I am going away" entry, we allow it to be added
	 */
	if (ce->ce_flags & CE_REMOVE)
		return 0;

	/*
	 * We check if the path is a sub-path of a subsequent pathname
	 * first, since removing those will not change the position
	 * in the array.
	 */
	retval = has_file_name(istate, ce, pos, ok_to_replace);

	/*
	 * Then check if the path might have a clashing sub-directory
	 * before it.
	 */
	return retval + has_dir_name(istate, ce, pos, ok_to_replace);
}

static int add_index_entry_with_check(struct index_state *istate, struct cache_entry *ce, int option)
{
	int pos;
	int ok_to_add = option & ADD_CACHE_OK_TO_ADD;
	int ok_to_replace = option & ADD_CACHE_OK_TO_REPLACE;
	int skip_df_check = option & ADD_CACHE_SKIP_DFCHECK;
	int new_only = option & ADD_CACHE_NEW_ONLY;

	cache_tree_invalidate_path(istate->cache_tree, ce->name);
	pos = index_name_pos(istate, ce->name, ce->ce_flags);

	/* existing match? Just replace it. */
	if (pos >= 0) {
		if (!new_only)
			replace_index_entry(istate, pos, ce);
		return 0;
	}
	pos = -pos-1;

	/*
	 * Inserting a merged entry ("stage 0") into the index
	 * will always replace all non-merged entries..
	 */
	if (pos < istate->cache_nr && ce_stage(ce) == 0) {
		while (ce_same_name(istate->cache[pos], ce)) {
			ok_to_add = 1;
			if (!remove_index_entry_at(istate, pos))
				break;
		}
	}

	if (!ok_to_add)
		return -1;
	if (!verify_path(ce->name))
		return error("Invalid path '%s'", ce->name);

	if (!skip_df_check &&
	    check_file_directory_conflict(istate, ce, pos, ok_to_replace)) {
		if (!ok_to_replace)
			return error("'%s' appears as both a file and as a directory",
				     ce->name);
		pos = index_name_pos(istate, ce->name, ce->ce_flags);
		pos = -pos-1;
	}
	return pos + 1;
}

int add_index_entry(struct index_state *istate, struct cache_entry *ce, int option)
{
	int pos;

	if (option & ADD_CACHE_JUST_APPEND)
		pos = istate->cache_nr;
	else {
		int ret;
		ret = add_index_entry_with_check(istate, ce, option);
		if (ret <= 0)
			return ret;
		pos = ret - 1;
	}

	/* Make sure the array is big enough .. */
	if (istate->cache_nr == istate->cache_alloc) {
		istate->cache_alloc = alloc_nr(istate->cache_alloc);
		istate->cache = xrealloc(istate->cache,
					istate->cache_alloc * sizeof(struct cache_entry *));
	}

	/* Add it in.. */
	istate->cache_nr++;
	if (istate->cache_nr > pos + 1)
		memmove(istate->cache + pos + 1,
			istate->cache + pos,
			(istate->cache_nr - pos - 1) * sizeof(ce));
	set_index_entry(istate, pos, ce);
	istate->cache_changed = 1;
	return 0;
}

/*
 * "refresh" does not calculate a new sha1 file or bring the
 * cache up-to-date for mode/content changes. But what it
 * _does_ do is to "re-match" the stat information of a file
 * with the cache, so that you can refresh the cache for a
 * file that hasn't been changed but where the stat entry is
 * out of date.
 *
 * For example, you'd want to do this after doing a "git-read-tree",
 * to link up the stat cache details with the proper files.
 */
static struct cache_entry *refresh_cache_ent(struct index_state *istate,
					     struct cache_entry *ce,
					     unsigned int options, int *err)
{
	struct stat st;
	struct cache_entry *updated;
	int changed, size;
	int ignore_valid = options & CE_MATCH_IGNORE_VALID;
	int ignore_skip_worktree = options & CE_MATCH_IGNORE_SKIP_WORKTREE;

	if (ce_uptodate(ce))
		return ce;

	/*
	 * CE_VALID or CE_SKIP_WORKTREE means the user promised us
	 * that the change to the work tree does not matter and told
	 * us not to worry.
	 */
	if (!ignore_skip_worktree && ce_skip_worktree(ce)) {
		ce_mark_uptodate(ce);
		return ce;
	}
	if (!ignore_valid && (ce->ce_flags & CE_VALID)) {
		ce_mark_uptodate(ce);
		return ce;
	}

	if (lstat(ce->name, &st) < 0) {
		if (err)
			*err = errno;
		return NULL;
	}

	changed = ie_match_stat(istate, ce, &st, options);
	if (!changed) {
		/*
		 * The path is unchanged.  If we were told to ignore
		 * valid bit, then we did the actual stat check and
		 * found that the entry is unmodified.  If the entry
		 * is not marked VALID, this is the place to mark it
		 * valid again, under "assume unchanged" mode.
		 */
		if (ignore_valid && assume_unchanged &&
		    !(ce->ce_flags & CE_VALID))
			; /* mark this one VALID again */
		else {
			/*
			 * We do not mark the index itself "modified"
			 * because CE_UPTODATE flag is in-core only;
			 * we are not going to write this change out.
			 */
			if (!S_ISGITLINK(ce->ce_mode))
				ce_mark_uptodate(ce);
			return ce;
		}
	}

	if (ie_modified(istate, ce, &st, options)) {
		if (err)
			*err = EINVAL;
		return NULL;
	}

	size = ce_size(ce);
	updated = xmalloc(size);
	memcpy(updated, ce, size);
	fill_stat_cache_info(updated, &st);
	/*
	 * If ignore_valid is not set, we should leave CE_VALID bit
	 * alone.  Otherwise, paths marked with --no-assume-unchanged
	 * (i.e. things to be edited) will reacquire CE_VALID bit
	 * automatically, which is not really what we want.
	 */
	if (!ignore_valid && assume_unchanged &&
	    !(ce->ce_flags & CE_VALID))
		updated->ce_flags &= ~CE_VALID;

	return updated;
}

static void show_file(const char * fmt, const char * name, int in_porcelain,
		      int * first, char *header_msg)
{
	if (in_porcelain && *first && header_msg) {
		printf("%s\n", header_msg);
		*first=0;
	}
	printf(fmt, name);
}

int refresh_index(struct index_state *istate, unsigned int flags, const char **pathspec,
		  char *seen, char *header_msg)
{
	int i;
	int has_errors = 0;
	int really = (flags & REFRESH_REALLY) != 0;
	int allow_unmerged = (flags & REFRESH_UNMERGED) != 0;
	int quiet = (flags & REFRESH_QUIET) != 0;
	int not_new = (flags & REFRESH_IGNORE_MISSING) != 0;
	int ignore_submodules = (flags & REFRESH_IGNORE_SUBMODULES) != 0;
	int first = 1;
	int in_porcelain = (flags & REFRESH_IN_PORCELAIN);
	unsigned int options = really ? CE_MATCH_IGNORE_VALID : 0;
	const char *needs_update_fmt;
	const char *needs_merge_fmt;

	needs_update_fmt = (in_porcelain ? "M\t%s\n" : "%s: needs update\n");
	needs_merge_fmt = (in_porcelain ? "U\t%s\n" : "%s: needs merge\n");
	for (i = 0; i < istate->cache_nr; i++) {
		struct cache_entry *ce, *new;
		int cache_errno = 0;

		ce = istate->cache[i];
		if (ignore_submodules && S_ISGITLINK(ce->ce_mode))
			continue;

		if (ce_stage(ce)) {
			while ((i < istate->cache_nr) &&
			       ! strcmp(istate->cache[i]->name, ce->name))
				i++;
			i--;
			if (allow_unmerged)
				continue;
			show_file(needs_merge_fmt, ce->name, in_porcelain, &first, header_msg);
			has_errors = 1;
			continue;
		}

		if (pathspec && !match_pathspec(pathspec, ce->name, strlen(ce->name), 0, seen))
			continue;

		new = refresh_cache_ent(istate, ce, options, &cache_errno);
		if (new == ce)
			continue;
		if (!new) {
			if (not_new && cache_errno == ENOENT)
				continue;
			if (really && cache_errno == EINVAL) {
				/* If we are doing --really-refresh that
				 * means the index is not valid anymore.
				 */
				ce->ce_flags &= ~CE_VALID;
				istate->cache_changed = 1;
			}
			if (quiet)
				continue;
			show_file(needs_update_fmt, ce->name, in_porcelain, &first, header_msg);
			has_errors = 1;
			continue;
		}

		replace_index_entry(istate, i, new);
	}
	return has_errors;
}

static struct cache_entry *refresh_cache_entry(struct cache_entry *ce, int really)
{
	return refresh_cache_ent(&the_index, ce, really, NULL);
}

static int verify_hdr(struct cache_header *hdr, unsigned long size)
{
	git_SHA_CTX c;
	unsigned char sha1[20];

	if (hdr->hdr_signature != htonl(CACHE_SIGNATURE))
		return error("bad signature");
	if (hdr->hdr_version != htonl(2) && hdr->hdr_version != htonl(3))
		return error("bad index version");
	git_SHA1_Init(&c);
	git_SHA1_Update(&c, hdr, size - 20);
	git_SHA1_Final(sha1, &c);
	if (hashcmp(sha1, (unsigned char *)hdr + size - 20))
		return error("bad index file sha1 signature");
	return 0;
}

static int read_index_extension(struct index_state *istate,
				const char *ext, void *data, unsigned long sz)
{
	switch (CACHE_EXT(ext)) {
	case CACHE_EXT_TREE:
		istate->cache_tree = cache_tree_read(data, sz);
		break;
	case CACHE_EXT_RESOLVE_UNDO:
		istate->resolve_undo = resolve_undo_read(data, sz);
		break;
	default:
		if (*ext < 'A' || 'Z' < *ext)
			return error("index uses %.4s extension, which we do not understand",
				     ext);
		fprintf(stderr, "ignoring %.4s extension\n", ext);
		break;
	}
	return 0;
}

int read_index(struct index_state *istate)
{
	return read_index_from(istate, get_index_file());
}

static void convert_from_disk(struct ondisk_cache_entry *ondisk, struct cache_entry *ce)
{
	size_t len;
	const char *name;

	ce->ce_ctime.sec = ntohl(ondisk->ctime.sec);
	ce->ce_mtime.sec = ntohl(ondisk->mtime.sec);
	ce->ce_ctime.nsec = ntohl(ondisk->ctime.nsec);
	ce->ce_mtime.nsec = ntohl(ondisk->mtime.nsec);
	ce->ce_dev   = ntohl(ondisk->dev);
	ce->ce_ino   = ntohl(ondisk->ino);
	ce->ce_mode  = ntohl(ondisk->mode);
	ce->ce_uid   = ntohl(ondisk->uid);
	ce->ce_gid   = ntohl(ondisk->gid);
	ce->ce_size  = ntohl(ondisk->size);
	/* On-disk flags are just 16 bits */
	ce->ce_flags = ntohs(ondisk->flags);

	hashcpy(ce->sha1, ondisk->sha1);

	len = ce->ce_flags & CE_NAMEMASK;

	if (ce->ce_flags & CE_EXTENDED) {
		struct ondisk_cache_entry_extended *ondisk2;
		int extended_flags;
		ondisk2 = (struct ondisk_cache_entry_extended *)ondisk;
		extended_flags = ntohs(ondisk2->flags2) << 16;
		/* We do not yet understand any bit out of CE_EXTENDED_FLAGS */
		if (extended_flags & ~CE_EXTENDED_FLAGS)
			die("Unknown index entry format %08x", extended_flags);
		ce->ce_flags |= extended_flags;
		name = ondisk2->name;
	}
	else
		name = ondisk->name;

	if (len == CE_NAMEMASK)
		len = strlen(name);
	/*
	 * NEEDSWORK: If the original index is crafted, this copy could
	 * go unchecked.
	 */
	memcpy(ce->name, name, len + 1);
}

static inline size_t estimate_cache_size(size_t ondisk_size, unsigned int entries)
{
	long per_entry;

	per_entry = sizeof(struct cache_entry) - sizeof(struct ondisk_cache_entry);

	/*
	 * Alignment can cause differences. This should be "alignof", but
	 * since that's a gcc'ism, just use the size of a pointer.
	 */
	per_entry += sizeof(void *);
	return ondisk_size + entries*per_entry;
}

/* remember to discard_cache() before reading a different cache! */
int read_index_from(struct index_state *istate, const char *path)
{
	int fd, i;
	struct stat st;
	unsigned long src_offset, dst_offset;
	struct cache_header *hdr;
	void *mmap;
	size_t mmap_size;

	errno = EBUSY;
	if (istate->initialized)
		return istate->cache_nr;

	errno = ENOENT;
	istate->timestamp.sec = 0;
	istate->timestamp.nsec = 0;
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		if (errno == ENOENT)
			return 0;
		die_errno("index file open failed");
	}

	if (fstat(fd, &st))
		die_errno("cannot stat the open index");

	errno = EINVAL;
	mmap_size = xsize_t(st.st_size);
	if (mmap_size < sizeof(struct cache_header) + 20)
		die("index file smaller than expected");

	mmap = xmmap(NULL, mmap_size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	close(fd);
	if (mmap == MAP_FAILED)
		die_errno("unable to map index file");

	hdr = mmap;
	if (verify_hdr(hdr, mmap_size) < 0)
		goto unmap;

	istate->cache_nr = ntohl(hdr->hdr_entries);
	istate->cache_alloc = alloc_nr(istate->cache_nr);
	istate->cache = xcalloc(istate->cache_alloc, sizeof(struct cache_entry *));

	/*
	 * The disk format is actually larger than the in-memory format,
	 * due to space for nsec etc, so even though the in-memory one
	 * has room for a few  more flags, we can allocate using the same
	 * index size
	 */
	istate->alloc = xmalloc(estimate_cache_size(mmap_size, istate->cache_nr));
	istate->initialized = 1;

	src_offset = sizeof(*hdr);
	dst_offset = 0;
	for (i = 0; i < istate->cache_nr; i++) {
		struct ondisk_cache_entry *disk_ce;
		struct cache_entry *ce;

		disk_ce = (struct ondisk_cache_entry *)((char *)mmap + src_offset);
		ce = (struct cache_entry *)((char *)istate->alloc + dst_offset);
		convert_from_disk(disk_ce, ce);
		set_index_entry(istate, i, ce);

		src_offset += ondisk_ce_size(ce);
		dst_offset += ce_size(ce);
	}
	istate->timestamp.sec = st.st_mtime;
	istate->timestamp.nsec = ST_MTIME_NSEC(st);

	while (src_offset <= mmap_size - 20 - 8) {
		/* After an array of active_nr index entries,
		 * there can be arbitrary number of extended
		 * sections, each of which is prefixed with
		 * extension name (4-byte) and section length
		 * in 4-byte network byte order.
		 */
		uint32_t extsize;
		memcpy(&extsize, (char *)mmap + src_offset + 4, 4);
		extsize = ntohl(extsize);
		if (read_index_extension(istate,
					 (const char *) mmap + src_offset,
					 (char *) mmap + src_offset + 8,
					 extsize) < 0)
			goto unmap;
		src_offset += 8;
		src_offset += extsize;
	}
	munmap(mmap, mmap_size);
	return istate->cache_nr;

unmap:
	munmap(mmap, mmap_size);
	errno = EINVAL;
	die("index file corrupt");
}

int is_index_unborn(struct index_state *istate)
{
	return (!istate->cache_nr && !istate->alloc && !istate->timestamp.sec);
}

int discard_index(struct index_state *istate)
{
	resolve_undo_clear_index(istate);
	istate->cache_nr = 0;
	istate->cache_changed = 0;
	istate->timestamp.sec = 0;
	istate->timestamp.nsec = 0;
	istate->name_hash_initialized = 0;
	free_hash(&istate->name_hash);
	cache_tree_free(&(istate->cache_tree));
	free(istate->alloc);
	istate->alloc = NULL;
	istate->initialized = 0;

	/* no need to throw away allocated active_cache */
	return 0;
}

int unmerged_index(const struct index_state *istate)
{
	int i;
	for (i = 0; i < istate->cache_nr; i++) {
		if (ce_stage(istate->cache[i]))
			return 1;
	}
	return 0;
}

#define WRITE_BUFFER_SIZE 8192
static unsigned char write_buffer[WRITE_BUFFER_SIZE];
static unsigned long write_buffer_len;

static int ce_write_flush(git_SHA_CTX *context, int fd)
{
	unsigned int buffered = write_buffer_len;
	if (buffered) {
		git_SHA1_Update(context, write_buffer, buffered);
		if (write_in_full(fd, write_buffer, buffered) != buffered)
			return -1;
		write_buffer_len = 0;
	}
	return 0;
}

static int ce_write(git_SHA_CTX *context, int fd, void *data, unsigned int len)
{
	while (len) {
		unsigned int buffered = write_buffer_len;
		unsigned int partial = WRITE_BUFFER_SIZE - buffered;
		if (partial > len)
			partial = len;
		memcpy(write_buffer + buffered, data, partial);
		buffered += partial;
		if (buffered == WRITE_BUFFER_SIZE) {
			write_buffer_len = buffered;
			if (ce_write_flush(context, fd))
				return -1;
			buffered = 0;
		}
		write_buffer_len = buffered;
		len -= partial;
		data = (char *) data + partial;
	}
	return 0;
}

static int write_index_ext_header(git_SHA_CTX *context, int fd,
				  unsigned int ext, unsigned int sz)
{
	ext = htonl(ext);
	sz = htonl(sz);
	return ((ce_write(context, fd, &ext, 4) < 0) ||
		(ce_write(context, fd, &sz, 4) < 0)) ? -1 : 0;
}

static int ce_flush(git_SHA_CTX *context, int fd)
{
	unsigned int left = write_buffer_len;

	if (left) {
		write_buffer_len = 0;
		git_SHA1_Update(context, write_buffer, left);
	}

	/* Flush first if not enough space for SHA1 signature */
	if (left + 20 > WRITE_BUFFER_SIZE) {
		if (write_in_full(fd, write_buffer, left) != left)
			return -1;
		left = 0;
	}

	/* Append the SHA1 signature at the end */
	git_SHA1_Final(write_buffer + left, context);
	left += 20;
	return (write_in_full(fd, write_buffer, left) != left) ? -1 : 0;
}

static void ce_smudge_racily_clean_entry(struct cache_entry *ce)
{
	/*
	 * The only thing we care about in this function is to smudge the
	 * falsely clean entry due to touch-update-touch race, so we leave
	 * everything else as they are.  We are called for entries whose
	 * ce_mtime match the index file mtime.
	 *
	 * Note that this actually does not do much for gitlinks, for
	 * which ce_match_stat_basic() always goes to the actual
	 * contents.  The caller checks with is_racy_timestamp() which
	 * always says "no" for gitlinks, so we are not called for them ;-)
	 */
	struct stat st;

	if (lstat(ce->name, &st) < 0)
		return;
	if (ce_match_stat_basic(ce, &st))
		return;
	if (ce_modified_check_fs(ce, &st)) {
		/* This is "racily clean"; smudge it.  Note that this
		 * is a tricky code.  At first glance, it may appear
		 * that it can break with this sequence:
		 *
		 * $ echo xyzzy >frotz
		 * $ git-update-index --add frotz
		 * $ : >frotz
		 * $ sleep 3
		 * $ echo filfre >nitfol
		 * $ git-update-index --add nitfol
		 *
		 * but it does not.  When the second update-index runs,
		 * it notices that the entry "frotz" has the same timestamp
		 * as index, and if we were to smudge it by resetting its
		 * size to zero here, then the object name recorded
		 * in index is the 6-byte file but the cached stat information
		 * becomes zero --- which would then match what we would
		 * obtain from the filesystem next time we stat("frotz").
		 *
		 * However, the second update-index, before calling
		 * this function, notices that the cached size is 6
		 * bytes and what is on the filesystem is an empty
		 * file, and never calls us, so the cached size information
		 * for "frotz" stays 6 which does not match the filesystem.
		 */
		ce->ce_size = 0;
	}
}

static int ce_write_entry(git_SHA_CTX *c, int fd, struct cache_entry *ce)
{
	int size = ondisk_ce_size(ce);
	struct ondisk_cache_entry *ondisk = xcalloc(1, size);
	char *name;
	int result;

	ondisk->ctime.sec = htonl(ce->ce_ctime.sec);
	ondisk->mtime.sec = htonl(ce->ce_mtime.sec);
	ondisk->ctime.nsec = htonl(ce->ce_ctime.nsec);
	ondisk->mtime.nsec = htonl(ce->ce_mtime.nsec);
	ondisk->dev  = htonl(ce->ce_dev);
	ondisk->ino  = htonl(ce->ce_ino);
	ondisk->mode = htonl(ce->ce_mode);
	ondisk->uid  = htonl(ce->ce_uid);
	ondisk->gid  = htonl(ce->ce_gid);
	ondisk->size = htonl(ce->ce_size);
	hashcpy(ondisk->sha1, ce->sha1);
	ondisk->flags = htons(ce->ce_flags);
	if (ce->ce_flags & CE_EXTENDED) {
		struct ondisk_cache_entry_extended *ondisk2;
		ondisk2 = (struct ondisk_cache_entry_extended *)ondisk;
		ondisk2->flags2 = htons((ce->ce_flags & CE_EXTENDED_FLAGS) >> 16);
		name = ondisk2->name;
	}
	else
		name = ondisk->name;
	memcpy(name, ce->name, ce_namelen(ce));

	result = ce_write(c, fd, ondisk, size);
	free(ondisk);
	return result;
}

int write_index(struct index_state *istate, int newfd)
{
	git_SHA_CTX c;
	struct cache_header hdr;
	int i, err, removed, extended;
	struct cache_entry **cache = istate->cache;
	int entries = istate->cache_nr;
	struct stat st;

	for (i = removed = extended = 0; i < entries; i++) {
		if (cache[i]->ce_flags & CE_REMOVE)
			removed++;

		/* reduce extended entries if possible */
		cache[i]->ce_flags &= ~CE_EXTENDED;
		if (cache[i]->ce_flags & CE_EXTENDED_FLAGS) {
			extended++;
			cache[i]->ce_flags |= CE_EXTENDED;
		}
	}

	hdr.hdr_signature = htonl(CACHE_SIGNATURE);
	/* for extended format, increase version so older git won't try to read it */
	hdr.hdr_version = htonl(extended ? 3 : 2);
	hdr.hdr_entries = htonl(entries - removed);

	git_SHA1_Init(&c);
	if (ce_write(&c, newfd, &hdr, sizeof(hdr)) < 0)
		return -1;

	for (i = 0; i < entries; i++) {
		struct cache_entry *ce = cache[i];
		if (ce->ce_flags & CE_REMOVE)
			continue;
		if (!ce_uptodate(ce) && is_racy_timestamp(istate, ce))
			ce_smudge_racily_clean_entry(ce);
		if (ce_write_entry(&c, newfd, ce) < 0)
			return -1;
	}

	/* Write extension data here */
	if (istate->cache_tree) {
		struct strbuf sb = STRBUF_INIT;

		cache_tree_write(&sb, istate->cache_tree);
		err = write_index_ext_header(&c, newfd, CACHE_EXT_TREE, sb.len) < 0
			|| ce_write(&c, newfd, sb.buf, sb.len) < 0;
		strbuf_release(&sb);
		if (err)
			return -1;
	}
	if (istate->resolve_undo) {
		struct strbuf sb = STRBUF_INIT;

		resolve_undo_write(&sb, istate->resolve_undo);
		err = write_index_ext_header(&c, newfd, CACHE_EXT_RESOLVE_UNDO,
					     sb.len) < 0
			|| ce_write(&c, newfd, sb.buf, sb.len) < 0;
		strbuf_release(&sb);
		if (err)
			return -1;
	}

	if (ce_flush(&c, newfd) || fstat(newfd, &st))
		return -1;
	istate->timestamp.sec = (unsigned int)st.st_mtime;
	istate->timestamp.nsec = ST_MTIME_NSEC(st);
	return 0;
}

/*
 * Read the index file that is potentially unmerged into given
 * index_state, dropping any unmerged entries.  Returns true if
 * the index is unmerged.  Callers who want to refuse to work
 * from an unmerged state can call this and check its return value,
 * instead of calling read_cache().
 */
int read_index_unmerged(struct index_state *istate)
{
	int i;
	int unmerged = 0;

	read_index(istate);
	for (i = 0; i < istate->cache_nr; i++) {
		struct cache_entry *ce = istate->cache[i];
		struct cache_entry *new_ce;
		int size, len;

		if (!ce_stage(ce))
			continue;
		unmerged = 1;
		len = strlen(ce->name);
		size = cache_entry_size(len);
		new_ce = xcalloc(1, size);
		memcpy(new_ce->name, ce->name, len);
		new_ce->ce_flags = create_ce_flags(len, 0) | CE_CONFLICTED;
		new_ce->ce_mode = ce->ce_mode;
		if (add_index_entry(istate, new_ce, 0))
			return error("%s: cannot drop to stage #0",
				     ce->name);
		i = index_name_pos(istate, new_ce->name, len);
	}
	return unmerged;
}

/*
 * Returns 1 if the path is an "other" path with respect to
 * the index; that is, the path is not mentioned in the index at all,
 * either as a file, a directory with some files in the index,
 * or as an unmerged entry.
 *
 * We helpfully remove a trailing "/" from directories so that
 * the output of read_directory can be used as-is.
 */
int index_name_is_other(const struct index_state *istate, const char *name,
		int namelen)
{
	int pos;
	if (namelen && name[namelen - 1] == '/')
		namelen--;
	pos = index_name_pos(istate, name, namelen);
	if (0 <= pos)
		return 0;	/* exact match */
	pos = -pos - 1;
	if (pos < istate->cache_nr) {
		struct cache_entry *ce = istate->cache[pos];
		if (ce_namelen(ce) == namelen &&
		    !memcmp(ce->name, name, namelen))
			return 0; /* Yup, this one exists unmerged */
	}
	return 1;
}
