/*
 * Builtin "git clone"
 *
 * Copyright (c) 2007 Kristian Høgsberg <krh@redhat.com>,
 *		 2008 Daniel Barkalow <barkalow@iabervon.org>
 * Based on git-commit.sh by Junio C Hamano and Linus Torvalds
 *
 * Clone a repository into a different directory that does not yet exist.
 */

#include "cache.h"
#include "parse-options.h"
#include "fetch-pack.h"
#include "refs.h"
#include "tree.h"
#include "tree-walk.h"
#include "unpack-trees.h"
#include "transport.h"
#include "strbuf.h"
#include "dir.h"
#include "pack-refs.h"
#include "sigchain.h"
#include "branch.h"
#include "remote.h"
#include "run-command.h"

/*
 * Overall FIXMEs:
 *  - respect DB_ENVIRONMENT for .git/objects.
 *
 * Implementation notes:
 *  - dropping use-separate-remote and no-separate-remote compatibility
 *
 */
static const char * const builtin_clone_usage[] = {
	"git clone [options] [--] <repo> [<dir>]",
	NULL
};

static int option_no_checkout, option_bare, option_mirror;
static int option_local, option_no_hardlinks, option_shared, option_recursive;
static char *option_template, *option_reference, *option_depth;
static char *option_origin = NULL;
static char *option_branch = NULL;
static char *option_upload_pack = "git-upload-pack";
static int option_verbosity;
static int option_progress;

static struct option builtin_clone_options[] = {
	OPT__VERBOSITY(&option_verbosity),
	OPT_BOOLEAN(0, "progress", &option_progress,
			"force progress reporting"),
	OPT_BOOLEAN('n', "no-checkout", &option_no_checkout,
		    "don't create a checkout"),
	OPT_BOOLEAN(0, "bare", &option_bare, "create a bare repository"),
	{ OPTION_BOOLEAN, 0, "naked", &option_bare, NULL,
		"create a bare repository",
		PARSE_OPT_NOARG | PARSE_OPT_HIDDEN },
	OPT_BOOLEAN(0, "mirror", &option_mirror,
		    "create a mirror repository (implies bare)"),
	OPT_BOOLEAN('l', "local", &option_local,
		    "to clone from a local repository"),
	OPT_BOOLEAN(0, "no-hardlinks", &option_no_hardlinks,
		    "don't use local hardlinks, always copy"),
	OPT_BOOLEAN('s', "shared", &option_shared,
		    "setup as shared repository"),
	OPT_BOOLEAN(0, "recursive", &option_recursive,
		    "initialize submodules in the clone"),
	OPT_BOOLEAN(0, "recurse-submodules", &option_recursive,
		    "initialize submodules in the clone"),
	OPT_STRING(0, "template", &option_template, "path",
		   "path the template repository"),
	OPT_STRING(0, "reference", &option_reference, "repo",
		   "reference repository"),
	OPT_STRING('o', "origin", &option_origin, "branch",
		   "use <branch> instead of 'origin' to track upstream"),
	OPT_STRING('b', "branch", &option_branch, "branch",
		   "checkout <branch> instead of the remote's HEAD"),
	OPT_STRING('u', "upload-pack", &option_upload_pack, "path",
		   "path to git-upload-pack on the remote"),
	OPT_STRING(0, "depth", &option_depth, "depth",
		    "create a shallow clone of that depth"),

	OPT_END()
};

static const char *argv_submodule[] = {
	"submodule", "update", "--init", "--recursive", NULL
};

static char *get_repo_path(const char *repo, int *is_bundle)
{
	static char *suffix[] = { "/.git", ".git", "" };
	static char *bundle_suffix[] = { ".bundle", "" };
	struct stat st;
	int i;

	for (i = 0; i < ARRAY_SIZE(suffix); i++) {
		const char *path;
		path = mkpath("%s%s", repo, suffix[i]);
		if (is_directory(path)) {
			*is_bundle = 0;
			return xstrdup(make_nonrelative_path(path));
		}
	}

	for (i = 0; i < ARRAY_SIZE(bundle_suffix); i++) {
		const char *path;
		path = mkpath("%s%s", repo, bundle_suffix[i]);
		if (!stat(path, &st) && S_ISREG(st.st_mode)) {
			*is_bundle = 1;
			return xstrdup(make_nonrelative_path(path));
		}
	}

	return NULL;
}

static char *guess_dir_name(const char *repo, int is_bundle, int is_bare)
{
	const char *end = repo + strlen(repo), *start;
	char *dir;

	/*
	 * Strip trailing spaces, slashes and /.git
	 */
	while (repo < end && (is_dir_sep(end[-1]) || isspace(end[-1])))
		end--;
	if (end - repo > 5 && is_dir_sep(end[-5]) &&
	    !strncmp(end - 4, ".git", 4)) {
		end -= 5;
		while (repo < end && is_dir_sep(end[-1]))
			end--;
	}

	/*
	 * Find last component, but be prepared that repo could have
	 * the form  "remote.example.com:foo.git", i.e. no slash
	 * in the directory part.
	 */
	start = end;
	while (repo < start && !is_dir_sep(start[-1]) && start[-1] != ':')
		start--;

	/*
	 * Strip .{bundle,git}.
	 */
	if (is_bundle) {
		if (end - start > 7 && !strncmp(end - 7, ".bundle", 7))
			end -= 7;
	} else {
		if (end - start > 4 && !strncmp(end - 4, ".git", 4))
			end -= 4;
	}

	if (is_bare) {
		struct strbuf result = STRBUF_INIT;
		strbuf_addf(&result, "%.*s.git", (int)(end - start), start);
		dir = strbuf_detach(&result, NULL);
	} else
		dir = xstrndup(start, end - start);
	/*
	 * Replace sequences of 'control' characters and whitespace
	 * with one ascii space, remove leading and trailing spaces.
	 */
	if (*dir) {
		char *out = dir;
		int prev_space = 1 /* strip leading whitespace */;
		for (end = dir; *end; ++end) {
			char ch = *end;
			if ((unsigned char)ch < '\x20')
				ch = '\x20';
			if (isspace(ch)) {
				if (prev_space)
					continue;
				prev_space = 1;
			} else
				prev_space = 0;
			*out++ = ch;
		}
		*out = '\0';
		if (out > dir && prev_space)
			out[-1] = '\0';
	}
	return dir;
}

static void strip_trailing_slashes(char *dir)
{
	char *end = dir + strlen(dir);

	while (dir < end - 1 && is_dir_sep(end[-1]))
		end--;
	*end = '\0';
}

static void setup_reference(const char *repo)
{
	const char *ref_git;
	char *ref_git_copy;

	struct remote *remote;
	struct transport *transport;
	const struct ref *extra;

	ref_git = make_absolute_path(option_reference);

	if (is_directory(mkpath("%s/.git/objects", ref_git)))
		ref_git = mkpath("%s/.git", ref_git);
	else if (!is_directory(mkpath("%s/objects", ref_git)))
		die("reference repository '%s' is not a local directory.",
		    option_reference);

	ref_git_copy = xstrdup(ref_git);

	add_to_alternates_file(ref_git_copy);

	remote = remote_get(ref_git_copy);
	transport = transport_get(remote, ref_git_copy);
	for (extra = transport_get_remote_refs(transport); extra;
	     extra = extra->next)
		add_extra_ref(extra->name, extra->old_sha1, 0);

	transport_disconnect(transport);

	free(ref_git_copy);
}

static void copy_or_link_directory(struct strbuf *src, struct strbuf *dest)
{
	struct dirent *de;
	struct stat buf;
	int src_len, dest_len;
	DIR *dir;

	dir = opendir(src->buf);
	if (!dir)
		die_errno("failed to open '%s'", src->buf);

	if (mkdir(dest->buf, 0777)) {
		if (errno != EEXIST)
			die_errno("failed to create directory '%s'", dest->buf);
		else if (stat(dest->buf, &buf))
			die_errno("failed to stat '%s'", dest->buf);
		else if (!S_ISDIR(buf.st_mode))
			die("%s exists and is not a directory", dest->buf);
	}

	strbuf_addch(src, '/');
	src_len = src->len;
	strbuf_addch(dest, '/');
	dest_len = dest->len;

	while ((de = readdir(dir)) != NULL) {
		strbuf_setlen(src, src_len);
		strbuf_addstr(src, de->d_name);
		strbuf_setlen(dest, dest_len);
		strbuf_addstr(dest, de->d_name);
		if (stat(src->buf, &buf)) {
			warning ("failed to stat %s\n", src->buf);
			continue;
		}
		if (S_ISDIR(buf.st_mode)) {
			if (de->d_name[0] != '.')
				copy_or_link_directory(src, dest);
			continue;
		}

		if (unlink(dest->buf) && errno != ENOENT)
			die_errno("failed to unlink '%s'", dest->buf);
		if (!option_no_hardlinks) {
			if (!link(src->buf, dest->buf))
				continue;
			if (option_local)
				die_errno("failed to create link '%s'", dest->buf);
			option_no_hardlinks = 1;
		}
		if (copy_file_with_time(dest->buf, src->buf, 0666))
			die_errno("failed to copy file to '%s'", dest->buf);
	}
	closedir(dir);
}

static const struct ref *clone_local(const char *src_repo,
				     const char *dest_repo)
{
	const struct ref *ret;
	struct strbuf src = STRBUF_INIT;
	struct strbuf dest = STRBUF_INIT;
	struct remote *remote;
	struct transport *transport;

	if (option_shared)
		add_to_alternates_file(src_repo);
	else {
		strbuf_addf(&src, "%s/objects", src_repo);
		strbuf_addf(&dest, "%s/objects", dest_repo);
		copy_or_link_directory(&src, &dest);
		strbuf_release(&src);
		strbuf_release(&dest);
	}

	remote = remote_get(src_repo);
	transport = transport_get(remote, src_repo);
	ret = transport_get_remote_refs(transport);
	transport_disconnect(transport);
	if (0 <= option_verbosity)
		printf("done.\n");
	return ret;
}

static const char *junk_work_tree;
static const char *junk_git_dir;
static pid_t junk_pid;

static void remove_junk(void)
{
	struct strbuf sb = STRBUF_INIT;
	if (getpid() != junk_pid)
		return;
	if (junk_git_dir) {
		strbuf_addstr(&sb, junk_git_dir);
		remove_dir_recursively(&sb, 0);
		strbuf_reset(&sb);
	}
	if (junk_work_tree) {
		strbuf_addstr(&sb, junk_work_tree);
		remove_dir_recursively(&sb, 0);
		strbuf_reset(&sb);
	}
}

static void remove_junk_on_signal(int signo)
{
	remove_junk();
	sigchain_pop(signo);
	raise(signo);
}

static struct ref *wanted_peer_refs(const struct ref *refs,
		struct refspec *refspec)
{
	struct ref *local_refs = NULL;
	struct ref **tail = &local_refs;

	get_fetch_map(refs, refspec, &tail, 0);
	if (!option_mirror)
		get_fetch_map(refs, tag_refspec, &tail, 0);

	return local_refs;
}

static void write_remote_refs(const struct ref *local_refs)
{
	const struct ref *r;

	for (r = local_refs; r; r = r->next)
		add_extra_ref(r->peer_ref->name, r->old_sha1, 0);

	pack_refs(PACK_REFS_ALL);
	clear_extra_refs();
}

int cmd_clone(int argc, const char **argv, const char *prefix)
{
	int is_bundle = 0, is_local;
	struct stat buf;
	const char *repo_name, *repo, *work_tree, *git_dir;
	char *path, *dir;
	int dest_exists;
	const struct ref *refs, *remote_head;
	const struct ref *remote_head_points_at;
	const struct ref *our_head_points_at;
	struct ref *mapped_refs;
	struct strbuf key = STRBUF_INIT, value = STRBUF_INIT;
	struct strbuf branch_top = STRBUF_INIT, reflog_msg = STRBUF_INIT;
	struct transport *transport = NULL;
	char *src_ref_prefix = "refs/heads/";
	int err = 0;

	struct refspec *refspec;
	const char *fetch_pattern;

	junk_pid = getpid();

	argc = parse_options(argc, argv, prefix, builtin_clone_options,
			     builtin_clone_usage, 0);

	if (argc > 2)
		usage_msg_opt("Too many arguments.",
			builtin_clone_usage, builtin_clone_options);

	if (argc == 0)
		usage_msg_opt("You must specify a repository to clone.",
			builtin_clone_usage, builtin_clone_options);

	if (option_mirror)
		option_bare = 1;

	if (option_bare) {
		if (option_origin)
			die("--bare and --origin %s options are incompatible.",
			    option_origin);
		option_no_checkout = 1;
	}

	if (!option_origin)
		option_origin = "origin";

	repo_name = argv[0];

	path = get_repo_path(repo_name, &is_bundle);
	if (path)
		repo = xstrdup(make_nonrelative_path(repo_name));
	else if (!strchr(repo_name, ':'))
		repo = xstrdup(make_absolute_path(repo_name));
	else
		repo = repo_name;
	is_local = path && !is_bundle;
	if (is_local && option_depth)
		warning("--depth is ignored in local clones; use file:// instead.");

	if (argc == 2)
		dir = xstrdup(argv[1]);
	else
		dir = guess_dir_name(repo_name, is_bundle, option_bare);
	strip_trailing_slashes(dir);

	dest_exists = !stat(dir, &buf);
	if (dest_exists && !is_empty_dir(dir))
		die("destination path '%s' already exists and is not "
			"an empty directory.", dir);

	strbuf_addf(&reflog_msg, "clone: from %s", repo);

	if (option_bare)
		work_tree = NULL;
	else {
		work_tree = getenv("GIT_WORK_TREE");
		if (work_tree && !stat(work_tree, &buf))
			die("working tree '%s' already exists.", work_tree);
	}

	if (option_bare || work_tree)
		git_dir = xstrdup(dir);
	else {
		work_tree = dir;
		git_dir = xstrdup(mkpath("%s/.git", dir));
	}

	if (!option_bare) {
		junk_work_tree = work_tree;
		if (safe_create_leading_directories_const(work_tree) < 0)
			die_errno("could not create leading directories of '%s'",
				  work_tree);
		if (!dest_exists && mkdir(work_tree, 0755))
			die_errno("could not create work tree dir '%s'.",
				  work_tree);
		set_git_work_tree(work_tree);
	}
	junk_git_dir = git_dir;
	atexit(remove_junk);
	sigchain_push_common(remove_junk_on_signal);

	setenv(CONFIG_ENVIRONMENT, mkpath("%s/config", git_dir), 1);

	if (safe_create_leading_directories_const(git_dir) < 0)
		die("could not create leading directories of '%s'", git_dir);
	set_git_dir(make_absolute_path(git_dir));

	if (0 <= option_verbosity)
		printf("Cloning into %s%s...\n",
		       option_bare ? "bare repository " : "", dir);
	init_db(option_template, INIT_DB_QUIET);

	/*
	 * At this point, the config exists, so we do not need the
	 * environment variable.  We actually need to unset it, too, to
	 * re-enable parsing of the global configs.
	 */
	unsetenv(CONFIG_ENVIRONMENT);

	git_config(git_default_config, NULL);

	if (option_bare) {
		if (option_mirror)
			src_ref_prefix = "refs/";
		strbuf_addstr(&branch_top, src_ref_prefix);

		git_config_set("core.bare", "true");
	} else {
		strbuf_addf(&branch_top, "refs/remotes/%s/", option_origin);
	}

	strbuf_addf(&value, "+%s*:%s*", src_ref_prefix, branch_top.buf);

	if (option_mirror || !option_bare) {
		/* Configure the remote */
		strbuf_addf(&key, "remote.%s.fetch", option_origin);
		git_config_set_multivar(key.buf, value.buf, "^$", 0);
		strbuf_reset(&key);

		if (option_mirror) {
			strbuf_addf(&key, "remote.%s.mirror", option_origin);
			git_config_set(key.buf, "true");
			strbuf_reset(&key);
		}
	}

	strbuf_addf(&key, "remote.%s.url", option_origin);
	git_config_set(key.buf, repo);
	strbuf_reset(&key);

	if (option_reference)
		setup_reference(git_dir);

	fetch_pattern = value.buf;
	refspec = parse_fetch_refspec(1, &fetch_pattern);

	strbuf_reset(&value);

	if (is_local) {
		refs = clone_local(path, git_dir);
		mapped_refs = wanted_peer_refs(refs, refspec);
	} else {
		struct remote *remote = remote_get(option_origin);
		transport = transport_get(remote, remote->url[0]);

		if (!transport->get_refs_list || !transport->fetch)
			die("Don't know how to clone %s", transport->url);

		transport_set_option(transport, TRANS_OPT_KEEP, "yes");

		if (option_depth)
			transport_set_option(transport, TRANS_OPT_DEPTH,
					     option_depth);

		transport_set_verbosity(transport, option_verbosity, option_progress);

		if (option_upload_pack)
			transport_set_option(transport, TRANS_OPT_UPLOADPACK,
					     option_upload_pack);

		refs = transport_get_remote_refs(transport);
		if (refs) {
			mapped_refs = wanted_peer_refs(refs, refspec);
			transport_fetch_refs(transport, mapped_refs);
		}
	}

	if (refs) {
		clear_extra_refs();

		write_remote_refs(mapped_refs);

		remote_head = find_ref_by_name(refs, "HEAD");
		remote_head_points_at =
			guess_remote_head(remote_head, mapped_refs, 0);

		if (option_branch) {
			struct strbuf head = STRBUF_INIT;
			strbuf_addstr(&head, src_ref_prefix);
			strbuf_addstr(&head, option_branch);
			our_head_points_at =
				find_ref_by_name(mapped_refs, head.buf);
			strbuf_release(&head);

			if (!our_head_points_at) {
				warning("Remote branch %s not found in "
					"upstream %s, using HEAD instead",
					option_branch, option_origin);
				our_head_points_at = remote_head_points_at;
			}
		}
		else
			our_head_points_at = remote_head_points_at;
	}
	else {
		warning("You appear to have cloned an empty repository.");
		our_head_points_at = NULL;
		remote_head_points_at = NULL;
		remote_head = NULL;
		option_no_checkout = 1;
		if (!option_bare)
			install_branch_config(0, "master", option_origin,
					      "refs/heads/master");
	}

	if (remote_head_points_at && !option_bare) {
		struct strbuf head_ref = STRBUF_INIT;
		strbuf_addstr(&head_ref, branch_top.buf);
		strbuf_addstr(&head_ref, "HEAD");
		create_symref(head_ref.buf,
			      remote_head_points_at->peer_ref->name,
			      reflog_msg.buf);
	}

	if (our_head_points_at) {
		/* Local default branch link */
		create_symref("HEAD", our_head_points_at->name, NULL);
		if (!option_bare) {
			const char *head = skip_prefix(our_head_points_at->name,
						       "refs/heads/");
			update_ref(reflog_msg.buf, "HEAD",
				   our_head_points_at->old_sha1,
				   NULL, 0, DIE_ON_ERR);
			install_branch_config(0, head, option_origin,
					      our_head_points_at->name);
		}
	} else if (remote_head) {
		/* Source had detached HEAD pointing somewhere. */
		if (!option_bare) {
			update_ref(reflog_msg.buf, "HEAD",
				   remote_head->old_sha1,
				   NULL, REF_NODEREF, DIE_ON_ERR);
			our_head_points_at = remote_head;
		}
	} else {
		/* Nothing to checkout out */
		if (!option_no_checkout)
			warning("remote HEAD refers to nonexistent ref, "
				"unable to checkout.\n");
		option_no_checkout = 1;
	}

	if (transport) {
		transport_unlock_pack(transport);
		transport_disconnect(transport);
	}

	if (!option_no_checkout) {
		struct lock_file *lock_file = xcalloc(1, sizeof(struct lock_file));
		struct unpack_trees_options opts;
		struct tree *tree;
		struct tree_desc t;
		int fd;

		/* We need to be in the new work tree for the checkout */
		setup_work_tree();

		fd = hold_locked_index(lock_file, 1);

		memset(&opts, 0, sizeof opts);
		opts.update = 1;
		opts.merge = 1;
		opts.fn = oneway_merge;
		opts.verbose_update = (option_verbosity > 0);
		opts.src_index = &the_index;
		opts.dst_index = &the_index;

		tree = parse_tree_indirect(our_head_points_at->old_sha1);
		parse_tree(tree);
		init_tree_desc(&t, tree->buffer, tree->size);
		unpack_trees(1, &t, &opts);

		if (write_cache(fd, active_cache, active_nr) ||
		    commit_locked_index(lock_file))
			die("unable to write new index file");

		err |= run_hook(NULL, "post-checkout", sha1_to_hex(null_sha1),
				sha1_to_hex(our_head_points_at->old_sha1), "1",
				NULL);

		if (!err && option_recursive)
			err = run_command_v_opt(argv_submodule, RUN_GIT_CMD);
	}

	strbuf_release(&reflog_msg);
	strbuf_release(&branch_top);
	strbuf_release(&key);
	strbuf_release(&value);
	junk_pid = 0;
	return err;
}
