/*
 * Copyright (C) 2008 Linus Torvalds
 */
#include "cache.h"

#ifdef NO_PTHREADS
static void preload_index(struct index_state *index, const char **pathspec)
{
	; /* nothing */
}
#else

#include <pthread.h>

/*
 * Mostly randomly chosen maximum thread counts: we
 * cap the parallelism to 20 threads, and we want
 * to have at least 500 lstat's per thread for it to
 * be worth starting a thread.
 */
#define MAX_PARALLEL (20)
#define THREAD_COST (500)

struct thread_data {
	pthread_t pthread;
	struct index_state *index;
	const char **pathspec;
	int offset, nr;
};

static void *preload_thread(void *_data)
{
	int nr;
	struct thread_data *p = _data;
	struct index_state *index = p->index;
	struct cache_entry **cep = index->cache + p->offset;
	struct cache_def cache;
	struct pathspec pathspec;

	init_pathspec(&pathspec, p->pathspec);
	memset(&cache, 0, sizeof(cache));
	nr = p->nr;
	if (nr + p->offset > index->cache_nr)
		nr = index->cache_nr - p->offset;

	do {
		struct cache_entry *ce = *cep++;
		struct stat st;

		if (ce_stage(ce))
			continue;
		if (S_ISGITLINK(ce->ce_mode))
			continue;
		if (ce_uptodate(ce))
			continue;
		if (!ce_path_match(ce, &pathspec))
			continue;
		if (threaded_has_symlink_leading_path(&cache, ce->name, ce_namelen(ce)))
			continue;
		if (lstat(ce->name, &st))
			continue;
		if (ie_match_stat(index, ce, &st, CE_MATCH_RACY_IS_DIRTY))
			continue;
		ce_mark_uptodate(ce);
	} while (--nr > 0);
	free_pathspec(&pathspec);
	return NULL;
}

static void preload_index(struct index_state *index, const char **pathspec)
{
	int threads, i, work, offset;
	struct thread_data data[MAX_PARALLEL];

	if (!core_preload_index)
		return;

	threads = index->cache_nr / THREAD_COST;
	if (threads < 2)
		return;
	if (threads > MAX_PARALLEL)
		threads = MAX_PARALLEL;
	offset = 0;
	work = DIV_ROUND_UP(index->cache_nr, threads);
	for (i = 0; i < threads; i++) {
		struct thread_data *p = data+i;
		p->index = index;
		p->pathspec = pathspec;
		p->offset = offset;
		p->nr = work;
		offset += work;
		if (pthread_create(&p->pthread, NULL, preload_thread, p))
			die("unable to create threaded lstat");
	}
	for (i = 0; i < threads; i++) {
		struct thread_data *p = data+i;
		if (pthread_join(p->pthread, NULL))
			die("unable to join threaded lstat");
	}
}
#endif

int read_index_preload(struct index_state *index, const char **pathspec)
{
	int retval = read_index(index);

	preload_index(index, pathspec);
	return retval;
}
