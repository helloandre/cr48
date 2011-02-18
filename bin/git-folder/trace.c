/*
 * GIT - The information manager from hell
 *
 * Copyright (C) 2000-2002 Michael R. Elkins <me@mutt.org>
 * Copyright (C) 2002-2004 Oswald Buddenhagen <ossi@users.sf.net>
 * Copyright (C) 2004 Theodore Y. Ts'o <tytso@mit.edu>
 * Copyright (C) 2006 Mike McCormack
 * Copyright (C) 2006 Christian Couder
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "cache.h"
#include "quote.h"

/* Get a trace file descriptor from GIT_TRACE env variable. */
static int get_trace_fd(int *need_close)
{
	char *trace = getenv("GIT_TRACE");

	if (!trace || !strcmp(trace, "") ||
	    !strcmp(trace, "0") || !strcasecmp(trace, "false"))
		return 0;
	if (!strcmp(trace, "1") || !strcasecmp(trace, "true"))
		return STDERR_FILENO;
	if (strlen(trace) == 1 && isdigit(*trace))
		return atoi(trace);
	if (is_absolute_path(trace)) {
		int fd = open(trace, O_WRONLY | O_APPEND | O_CREAT, 0666);
		if (fd == -1) {
			fprintf(stderr,
				"Could not open '%s' for tracing: %s\n"
				"Defaulting to tracing on stderr...\n",
				trace, strerror(errno));
			return STDERR_FILENO;
		}
		*need_close = 1;
		return fd;
	}

	fprintf(stderr, "What does '%s' for GIT_TRACE mean?\n", trace);
	fprintf(stderr, "If you want to trace into a file, "
		"then please set GIT_TRACE to an absolute pathname "
		"(starting with /).\n");
	fprintf(stderr, "Defaulting to tracing on stderr...\n");

	return STDERR_FILENO;
}

static const char err_msg[] = "Could not trace into fd given by "
	"GIT_TRACE environment variable";

void trace_printf(const char *fmt, ...)
{
	struct strbuf buf;
	va_list ap;
	int fd, len, need_close = 0;

	fd = get_trace_fd(&need_close);
	if (!fd)
		return;

	set_try_to_free_routine(NULL);	/* is never reset */
	strbuf_init(&buf, 64);
	va_start(ap, fmt);
	len = vsnprintf(buf.buf, strbuf_avail(&buf), fmt, ap);
	va_end(ap);
	if (len >= strbuf_avail(&buf)) {
		strbuf_grow(&buf, len - strbuf_avail(&buf) + 128);
		va_start(ap, fmt);
		len = vsnprintf(buf.buf, strbuf_avail(&buf), fmt, ap);
		va_end(ap);
		if (len >= strbuf_avail(&buf))
			die("broken vsnprintf");
	}
	strbuf_setlen(&buf, len);

	write_or_whine_pipe(fd, buf.buf, buf.len, err_msg);
	strbuf_release(&buf);

	if (need_close)
		close(fd);
}

void trace_argv_printf(const char **argv, const char *fmt, ...)
{
	struct strbuf buf;
	va_list ap;
	int fd, len, need_close = 0;

	fd = get_trace_fd(&need_close);
	if (!fd)
		return;

	set_try_to_free_routine(NULL);	/* is never reset */
	strbuf_init(&buf, 64);
	va_start(ap, fmt);
	len = vsnprintf(buf.buf, strbuf_avail(&buf), fmt, ap);
	va_end(ap);
	if (len >= strbuf_avail(&buf)) {
		strbuf_grow(&buf, len - strbuf_avail(&buf) + 128);
		va_start(ap, fmt);
		len = vsnprintf(buf.buf, strbuf_avail(&buf), fmt, ap);
		va_end(ap);
		if (len >= strbuf_avail(&buf))
			die("broken vsnprintf");
	}
	strbuf_setlen(&buf, len);

	sq_quote_argv(&buf, argv, 0);
	strbuf_addch(&buf, '\n');
	write_or_whine_pipe(fd, buf.buf, buf.len, err_msg);
	strbuf_release(&buf);

	if (need_close)
		close(fd);
}

static const char *quote_crnl(const char *path)
{
	static char new_path[PATH_MAX];
	const char *p2 = path;
	char *p1 = new_path;

	if (!path)
		return NULL;

	while (*p2) {
		switch (*p2) {
		case '\\': *p1++ = '\\'; *p1++ = '\\'; break;
		case '\n': *p1++ = '\\'; *p1++ = 'n'; break;
		case '\r': *p1++ = '\\'; *p1++ = 'r'; break;
		default:
			*p1++ = *p2;
		}
		p2++;
	}
	*p1 = '\0';
	return new_path;
}

/* FIXME: move prefix to startup_info struct and get rid of this arg */
void trace_repo_setup(const char *prefix)
{
	const char *git_work_tree;
	char cwd[PATH_MAX];
	char *trace = getenv("GIT_TRACE");

	if (!trace || !strcmp(trace, "") ||
	    !strcmp(trace, "0") || !strcasecmp(trace, "false"))
		return;

	if (!getcwd(cwd, PATH_MAX))
		die("Unable to get current working directory");

	if (!(git_work_tree = get_git_work_tree()))
		git_work_tree = "(null)";

	if (!prefix)
		prefix = "(null)";

	trace_printf("setup: git_dir: %s\n", quote_crnl(get_git_dir()));
	trace_printf("setup: worktree: %s\n", quote_crnl(git_work_tree));
	trace_printf("setup: cwd: %s\n", quote_crnl(cwd));
	trace_printf("setup: prefix: %s\n", quote_crnl(prefix));
}
