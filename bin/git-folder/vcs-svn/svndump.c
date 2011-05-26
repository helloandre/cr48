/*
 * Parse and rearrange a svnadmin dump.
 * Create the dump with:
 * svnadmin dump --incremental -r<startrev>:<endrev> <repository> >outfile
 *
 * Licensed under a two-clause BSD-style license.
 * See LICENSE for details.
 */

#include "cache.h"
#include "repo_tree.h"
#include "fast_export.h"
#include "line_buffer.h"
#include "string_pool.h"
#include "strbuf.h"

/*
 * Compare start of string to literal of equal length;
 * must be guarded by length test.
 */
#define constcmp(s, ref) memcmp(s, ref, sizeof(ref) - 1)

#define NODEACT_REPLACE 4
#define NODEACT_DELETE 3
#define NODEACT_ADD 2
#define NODEACT_CHANGE 1
#define NODEACT_UNKNOWN 0

#define DUMP_CTX 0
#define REV_CTX  1
#define NODE_CTX 2

#define LENGTH_UNKNOWN (~0)
#define DATE_RFC2822_LEN 31

static struct line_buffer input = LINE_BUFFER_INIT;

static struct {
	uint32_t action, propLength, textLength, srcRev, type;
	uint32_t src[REPO_MAX_PATH_DEPTH], dst[REPO_MAX_PATH_DEPTH];
	uint32_t text_delta, prop_delta;
} node_ctx;

static struct {
	uint32_t revision;
	unsigned long timestamp;
	struct strbuf log, author;
} rev_ctx;

static struct {
	uint32_t version;
	struct strbuf uuid, url;
} dump_ctx;

static void reset_node_ctx(char *fname)
{
	node_ctx.type = 0;
	node_ctx.action = NODEACT_UNKNOWN;
	node_ctx.propLength = LENGTH_UNKNOWN;
	node_ctx.textLength = LENGTH_UNKNOWN;
	node_ctx.src[0] = ~0;
	node_ctx.srcRev = 0;
	pool_tok_seq(REPO_MAX_PATH_DEPTH, node_ctx.dst, "/", fname);
	node_ctx.text_delta = 0;
	node_ctx.prop_delta = 0;
}

static void reset_rev_ctx(uint32_t revision)
{
	rev_ctx.revision = revision;
	rev_ctx.timestamp = 0;
	strbuf_reset(&rev_ctx.log);
	strbuf_reset(&rev_ctx.author);
}

static void reset_dump_ctx(const char *url)
{
	strbuf_reset(&dump_ctx.url);
	if (url)
		strbuf_addstr(&dump_ctx.url, url);
	dump_ctx.version = 1;
	strbuf_reset(&dump_ctx.uuid);
}

static void handle_property(const struct strbuf *key_buf,
				struct strbuf *val,
				uint32_t *type_set)
{
	const char *key = key_buf->buf;
	size_t keylen = key_buf->len;

	switch (keylen + 1) {
	case sizeof("svn:log"):
		if (constcmp(key, "svn:log"))
			break;
		if (!val)
			die("invalid dump: unsets svn:log");
		strbuf_swap(&rev_ctx.log, val);
		break;
	case sizeof("svn:author"):
		if (constcmp(key, "svn:author"))
			break;
		if (!val)
			strbuf_reset(&rev_ctx.author);
		else
			strbuf_swap(&rev_ctx.author, val);
		break;
	case sizeof("svn:date"):
		if (constcmp(key, "svn:date"))
			break;
		if (!val)
			die("invalid dump: unsets svn:date");
		if (parse_date_basic(val->buf, &rev_ctx.timestamp, NULL))
			warning("invalid timestamp: %s", val->buf);
		break;
	case sizeof("svn:executable"):
	case sizeof("svn:special"):
		if (keylen == strlen("svn:executable") &&
		    constcmp(key, "svn:executable"))
			break;
		if (keylen == strlen("svn:special") &&
		    constcmp(key, "svn:special"))
			break;
		if (*type_set) {
			if (!val)
				return;
			die("invalid dump: sets type twice");
		}
		if (!val) {
			node_ctx.type = REPO_MODE_BLB;
			return;
		}
		*type_set = 1;
		node_ctx.type = keylen == strlen("svn:executable") ?
				REPO_MODE_EXE :
				REPO_MODE_LNK;
	}
}

static void die_short_read(void)
{
	if (buffer_ferror(&input))
		die_errno("error reading dump file");
	die("invalid dump: unexpected end of file");
}

static void read_props(void)
{
	static struct strbuf key = STRBUF_INIT;
	static struct strbuf val = STRBUF_INIT;
	const char *t;
	/*
	 * NEEDSWORK: to support simple mode changes like
	 *	K 11
	 *	svn:special
	 *	V 1
	 *	*
	 *	D 14
	 *	svn:executable
	 * we keep track of whether a mode has been set and reset to
	 * plain file only if not.  We should be keeping track of the
	 * symlink and executable bits separately instead.
	 */
	uint32_t type_set = 0;
	while ((t = buffer_read_line(&input)) && strcmp(t, "PROPS-END")) {
		uint32_t len;
		const char type = t[0];
		int ch;

		if (!type || t[1] != ' ')
			die("invalid property line: %s\n", t);
		len = atoi(&t[2]);
		strbuf_reset(&val);
		buffer_read_binary(&input, &val, len);
		if (val.len < len)
			die_short_read();

		/* Discard trailing newline. */
		ch = buffer_read_char(&input);
		if (ch == EOF)
			die_short_read();
		if (ch != '\n')
			die("invalid dump: expected newline after %s", val.buf);

		switch (type) {
		case 'K':
			strbuf_swap(&key, &val);
			continue;
		case 'D':
			handle_property(&val, NULL, &type_set);
			continue;
		case 'V':
			handle_property(&key, &val, &type_set);
			strbuf_reset(&key);
			continue;
		default:
			die("invalid property line: %s\n", t);
		}
	}
}

static void handle_node(void)
{
	uint32_t mark = 0;
	const uint32_t type = node_ctx.type;
	const int have_props = node_ctx.propLength != LENGTH_UNKNOWN;
	const int have_text = node_ctx.textLength != LENGTH_UNKNOWN;

	if (node_ctx.text_delta)
		die("text deltas not supported");
	if (have_text)
		mark = next_blob_mark();
	if (node_ctx.action == NODEACT_DELETE) {
		if (have_text || have_props || node_ctx.srcRev)
			die("invalid dump: deletion node has "
				"copyfrom info, text, or properties");
		repo_delete(node_ctx.dst);
		return;
	}
	if (node_ctx.action == NODEACT_REPLACE) {
		repo_delete(node_ctx.dst);
		node_ctx.action = NODEACT_ADD;
	}
	if (node_ctx.srcRev) {
		repo_copy(node_ctx.srcRev, node_ctx.src, node_ctx.dst);
		if (node_ctx.action == NODEACT_ADD)
			node_ctx.action = NODEACT_CHANGE;
	}
	if (have_text && type == REPO_MODE_DIR)
		die("invalid dump: directories cannot have text attached");

	/*
	 * Decide on the new content (mark) and mode (node_ctx.type).
	 */
	if (node_ctx.action == NODEACT_CHANGE && !~*node_ctx.dst) {
		if (type != REPO_MODE_DIR)
			die("invalid dump: root of tree is not a regular file");
	} else if (node_ctx.action == NODEACT_CHANGE) {
		uint32_t mode;
		if (!have_text)
			mark = repo_read_path(node_ctx.dst);
		mode = repo_read_mode(node_ctx.dst);
		if (mode == REPO_MODE_DIR && type != REPO_MODE_DIR)
			die("invalid dump: cannot modify a directory into a file");
		if (mode != REPO_MODE_DIR && type == REPO_MODE_DIR)
			die("invalid dump: cannot modify a file into a directory");
		node_ctx.type = mode;
	} else if (node_ctx.action == NODEACT_ADD) {
		if (!have_text && type != REPO_MODE_DIR)
			die("invalid dump: adds node without text");
	} else {
		die("invalid dump: Node-path block lacks Node-action");
	}

	/*
	 * Adjust mode to reflect properties.
	 */
	if (have_props) {
		if (!node_ctx.prop_delta)
			node_ctx.type = type;
		if (node_ctx.propLength)
			read_props();
	}

	/*
	 * Save the result.
	 */
	repo_add(node_ctx.dst, node_ctx.type, mark);
	if (have_text)
		fast_export_blob(node_ctx.type, mark,
				 node_ctx.textLength, &input);
}

static void handle_revision(void)
{
	if (rev_ctx.revision)
		repo_commit(rev_ctx.revision, rev_ctx.author.buf,
			&rev_ctx.log, dump_ctx.uuid.buf, dump_ctx.url.buf,
			rev_ctx.timestamp);
}

void svndump_read(const char *url)
{
	char *val;
	char *t;
	uint32_t active_ctx = DUMP_CTX;
	uint32_t len;

	reset_dump_ctx(url);
	while ((t = buffer_read_line(&input))) {
		val = strchr(t, ':');
		if (!val)
			continue;
		val++;
		if (*val != ' ')
			continue;
		val++;

		/* strlen(key) + 1 */
		switch (val - t - 1) {
		case sizeof("SVN-fs-dump-format-version"):
			if (constcmp(t, "SVN-fs-dump-format-version"))
				continue;
			dump_ctx.version = atoi(val);
			if (dump_ctx.version > 3)
				die("expected svn dump format version <= 3, found %"PRIu32,
				    dump_ctx.version);
			break;
		case sizeof("UUID"):
			if (constcmp(t, "UUID"))
				continue;
			strbuf_reset(&dump_ctx.uuid);
			strbuf_addstr(&dump_ctx.uuid, val);
			break;
		case sizeof("Revision-number"):
			if (constcmp(t, "Revision-number"))
				continue;
			if (active_ctx == NODE_CTX)
				handle_node();
			if (active_ctx != DUMP_CTX)
				handle_revision();
			active_ctx = REV_CTX;
			reset_rev_ctx(atoi(val));
			break;
		case sizeof("Node-path"):
			if (prefixcmp(t, "Node-"))
				continue;
			if (!constcmp(t + strlen("Node-"), "path")) {
				if (active_ctx == NODE_CTX)
					handle_node();
				active_ctx = NODE_CTX;
				reset_node_ctx(val);
				break;
			}
			if (constcmp(t + strlen("Node-"), "kind"))
				continue;
			if (!strcmp(val, "dir"))
				node_ctx.type = REPO_MODE_DIR;
			else if (!strcmp(val, "file"))
				node_ctx.type = REPO_MODE_BLB;
			else
				fprintf(stderr, "Unknown node-kind: %s\n", val);
			break;
		case sizeof("Node-action"):
			if (constcmp(t, "Node-action"))
				continue;
			if (!strcmp(val, "delete")) {
				node_ctx.action = NODEACT_DELETE;
			} else if (!strcmp(val, "add")) {
				node_ctx.action = NODEACT_ADD;
			} else if (!strcmp(val, "change")) {
				node_ctx.action = NODEACT_CHANGE;
			} else if (!strcmp(val, "replace")) {
				node_ctx.action = NODEACT_REPLACE;
			} else {
				fprintf(stderr, "Unknown node-action: %s\n", val);
				node_ctx.action = NODEACT_UNKNOWN;
			}
			break;
		case sizeof("Node-copyfrom-path"):
			if (constcmp(t, "Node-copyfrom-path"))
				continue;
			pool_tok_seq(REPO_MAX_PATH_DEPTH, node_ctx.src, "/", val);
			break;
		case sizeof("Node-copyfrom-rev"):
			if (constcmp(t, "Node-copyfrom-rev"))
				continue;
			node_ctx.srcRev = atoi(val);
			break;
		case sizeof("Text-content-length"):
			if (!constcmp(t, "Text-content-length")) {
				node_ctx.textLength = atoi(val);
				break;
			}
			if (constcmp(t, "Prop-content-length"))
				continue;
			node_ctx.propLength = atoi(val);
			break;
		case sizeof("Text-delta"):
			if (!constcmp(t, "Text-delta")) {
				node_ctx.text_delta = !strcmp(val, "true");
				break;
			}
			if (constcmp(t, "Prop-delta"))
				continue;
			node_ctx.prop_delta = !strcmp(val, "true");
			break;
		case sizeof("Content-length"):
			if (constcmp(t, "Content-length"))
				continue;
			len = atoi(val);
			t = buffer_read_line(&input);
			if (!t)
				die_short_read();
			if (*t)
				die("invalid dump: expected blank line after content length header");
			if (active_ctx == REV_CTX) {
				read_props();
			} else if (active_ctx == NODE_CTX) {
				handle_node();
				active_ctx = REV_CTX;
			} else {
				fprintf(stderr, "Unexpected content length header: %"PRIu32"\n", len);
				if (buffer_skip_bytes(&input, len) != len)
					die_short_read();
			}
		}
	}
	if (buffer_ferror(&input))
		die_short_read();
	if (active_ctx == NODE_CTX)
		handle_node();
	if (active_ctx != DUMP_CTX)
		handle_revision();
}

int svndump_init(const char *filename)
{
	if (buffer_init(&input, filename))
		return error("cannot open %s: %s", filename, strerror(errno));
	repo_init();
	strbuf_init(&dump_ctx.uuid, 4096);
	strbuf_init(&dump_ctx.url, 4096);
	strbuf_init(&rev_ctx.log, 4096);
	strbuf_init(&rev_ctx.author, 4096);
	reset_dump_ctx(NULL);
	reset_rev_ctx(0);
	reset_node_ctx(NULL);
	return 0;
}

void svndump_deinit(void)
{
	repo_reset();
	reset_dump_ctx(NULL);
	reset_rev_ctx(0);
	reset_node_ctx(NULL);
	strbuf_release(&rev_ctx.log);
	if (buffer_deinit(&input))
		fprintf(stderr, "Input error\n");
	if (ferror(stdout))
		fprintf(stderr, "Output error\n");
}

void svndump_reset(void)
{
	buffer_reset(&input);
	repo_reset();
	strbuf_release(&dump_ctx.uuid);
	strbuf_release(&dump_ctx.url);
	strbuf_release(&rev_ctx.log);
	strbuf_release(&rev_ctx.author);
}
