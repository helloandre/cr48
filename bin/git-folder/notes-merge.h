#ifndef NOTES_MERGE_H
#define NOTES_MERGE_H

#define NOTES_MERGE_WORKTREE "NOTES_MERGE_WORKTREE"

enum notes_merge_verbosity {
	NOTES_MERGE_VERBOSITY_DEFAULT = 2,
	NOTES_MERGE_VERBOSITY_MAX = 5
};

struct notes_merge_options {
	const char *local_ref;
	const char *remote_ref;
	struct strbuf commit_msg;
	int verbosity;
	enum {
		NOTES_MERGE_RESOLVE_MANUAL = 0,
		NOTES_MERGE_RESOLVE_OURS,
		NOTES_MERGE_RESOLVE_THEIRS,
		NOTES_MERGE_RESOLVE_UNION,
		NOTES_MERGE_RESOLVE_CAT_SORT_UNIQ
	} strategy;
	unsigned has_worktree:1;
};

void init_notes_merge_options(struct notes_merge_options *o);

/*
 * Create new notes commit from the given notes tree
 *
 * Properties of the created commit:
 * - tree: the result of converting t to a tree object with write_notes_tree().
 * - parents: the given parents OR (if NULL) the commit referenced by t->ref.
 * - author/committer: the default determined by commmit_tree().
 * - commit message: msg
 *
 * The resulting commit SHA1 is stored in result_sha1.
 */
void create_notes_commit(struct notes_tree *t, struct commit_list *parents,
			 const char *msg, unsigned char *result_sha1);

/*
 * Merge notes from o->remote_ref into o->local_ref
 *
 * The given notes_tree 'local_tree' must be the notes_tree referenced by the
 * o->local_ref. This is the notes_tree in which the object-level merge is
 * performed.
 *
 * The commits given by the two refs are merged, producing one of the following
 * outcomes:
 *
 * 1. The merge trivially results in an existing commit (e.g. fast-forward or
 *    already-up-to-date). 'local_tree' is untouched, the SHA1 of the result
 *    is written into 'result_sha1' and 0 is returned.
 * 2. The merge successfully completes, producing a merge commit. local_tree
 *    contains the updated notes tree, the SHA1 of the resulting commit is
 *    written into 'result_sha1', and 1 is returned.
 * 3. The merge results in conflicts. This is similar to #2 in that the
 *    partial merge result (i.e. merge result minus the unmerged entries)
 *    are stored in 'local_tree', and the SHA1 or the resulting commit
 *    (to be amended when the conflicts have been resolved) is written into
 *    'result_sha1'. The unmerged entries are written into the
 *    .git/NOTES_MERGE_WORKTREE directory with conflict markers.
 *    -1 is returned.
 *
 * Both o->local_ref and o->remote_ref must be given (non-NULL), but either ref
 * (although not both) may refer to a non-existing notes ref, in which case
 * that notes ref is interpreted as an empty notes tree, and the merge
 * trivially results in what the other ref points to.
 */
int notes_merge(struct notes_merge_options *o,
		struct notes_tree *local_tree,
		unsigned char *result_sha1);

/*
 * Finalize conflict resolution from an earlier notes_merge()
 *
 * The given notes tree 'partial_tree' must be the notes_tree corresponding to
 * the given 'partial_commit', the partial result commit created by a previous
 * call to notes_merge().
 *
 * This function will add the (now resolved) notes in .git/NOTES_MERGE_WORKTREE
 * to 'partial_tree', and create a final notes merge commit, the SHA1 of which
 * will be stored in 'result_sha1'.
 */
int notes_merge_commit(struct notes_merge_options *o,
		       struct notes_tree *partial_tree,
		       struct commit *partial_commit,
		       unsigned char *result_sha1);

/*
 * Abort conflict resolution from an earlier notes_merge()
 *
 * Removes the notes merge worktree in .git/NOTES_MERGE_WORKTREE.
 */
int notes_merge_abort(struct notes_merge_options *o);

#endif
