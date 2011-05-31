#include "cache.h"
#include "transport.h"
#include "quote.h"
#include "run-command.h"
#include "commit.h"
#include "diff.h"
#include "revision.h"
#include "quote.h"
#include "remote.h"
#include "string-list.h"
#include "thread-utils.h"

static int debug;

struct helper_data {
	const char *name;
	struct child_process *helper;
	FILE *out;
	unsigned fetch : 1,
		import : 1,
		export : 1,
		option : 1,
		push : 1,
		connect : 1,
		no_disconnect_req : 1;
	/* These go from remote name (as in "list") to private name */
	struct refspec *refspecs;
	int refspec_nr;
	/* Transport options for fetch-pack/send-pack (should one of
	 * those be invoked).
	 */
	struct git_transport_options transport_options;
};

static void sendline(struct helper_data *helper, struct strbuf *buffer)
{
	if (debug)
		fprintf(stderr, "Debug: Remote helper: -> %s", buffer->buf);
	if (write_in_full(helper->helper->in, buffer->buf, buffer->len)
		!= buffer->len)
		die_errno("Full write to remote helper failed");
}

static int recvline_fh(FILE *helper, struct strbuf *buffer)
{
	strbuf_reset(buffer);
	if (debug)
		fprintf(stderr, "Debug: Remote helper: Waiting...\n");
	if (strbuf_getline(buffer, helper, '\n') == EOF) {
		if (debug)
			fprintf(stderr, "Debug: Remote helper quit.\n");
		exit(128);
	}

	if (debug)
		fprintf(stderr, "Debug: Remote helper: <- %s\n", buffer->buf);
	return 0;
}

static int recvline(struct helper_data *helper, struct strbuf *buffer)
{
	return recvline_fh(helper->out, buffer);
}

static void xchgline(struct helper_data *helper, struct strbuf *buffer)
{
	sendline(helper, buffer);
	recvline(helper, buffer);
}

static void write_constant(int fd, const char *str)
{
	if (debug)
		fprintf(stderr, "Debug: Remote helper: -> %s", str);
	if (write_in_full(fd, str, strlen(str)) != strlen(str))
		die_errno("Full write to remote helper failed");
}

static const char *remove_ext_force(const char *url)
{
	if (url) {
		const char *colon = strchr(url, ':');
		if (colon && colon[1] == ':')
			return colon + 2;
	}
	return url;
}

static void do_take_over(struct transport *transport)
{
	struct helper_data *data;
	data = (struct helper_data *)transport->data;
	transport_take_over(transport, data->helper);
	fclose(data->out);
	free(data);
}

static struct child_process *get_helper(struct transport *transport)
{
	struct helper_data *data = transport->data;
	struct strbuf buf = STRBUF_INIT;
	struct child_process *helper;
	const char **refspecs = NULL;
	int refspec_nr = 0;
	int refspec_alloc = 0;
	int duped;
	int code;

	if (data->helper)
		return data->helper;

	helper = xcalloc(1, sizeof(*helper));
	helper->in = -1;
	helper->out = -1;
	helper->err = 0;
	helper->argv = xcalloc(4, sizeof(*helper->argv));
	strbuf_addf(&buf, "git-remote-%s", data->name);
	helper->argv[0] = strbuf_detach(&buf, NULL);
	helper->argv[1] = transport->remote->name;
	helper->argv[2] = remove_ext_force(transport->url);
	helper->git_cmd = 0;
	helper->silent_exec_failure = 1;
	code = start_command(helper);
	if (code < 0 && errno == ENOENT)
		die("Unable to find remote helper for '%s'", data->name);
	else if (code != 0)
		exit(code);

	data->helper = helper;
	data->no_disconnect_req = 0;

	/*
	 * Open the output as FILE* so strbuf_getline() can be used.
	 * Do this with duped fd because fclose() will close the fd,
	 * and stuff like taking over will require the fd to remain.
	 */
	duped = dup(helper->out);
	if (duped < 0)
		die_errno("Can't dup helper output fd");
	data->out = xfdopen(duped, "r");

	write_constant(helper->in, "capabilities\n");

	while (1) {
		const char *capname;
		int mandatory = 0;
		recvline(data, &buf);

		if (!*buf.buf)
			break;

		if (*buf.buf == '*') {
			capname = buf.buf + 1;
			mandatory = 1;
		} else
			capname = buf.buf;

		if (debug)
			fprintf(stderr, "Debug: Got cap %s\n", capname);
		if (!strcmp(capname, "fetch"))
			data->fetch = 1;
		else if (!strcmp(capname, "option"))
			data->option = 1;
		else if (!strcmp(capname, "push"))
			data->push = 1;
		else if (!strcmp(capname, "import"))
			data->import = 1;
		else if (!strcmp(capname, "export"))
			data->export = 1;
		else if (!data->refspecs && !prefixcmp(capname, "refspec ")) {
			ALLOC_GROW(refspecs,
				   refspec_nr + 1,
				   refspec_alloc);
			refspecs[refspec_nr++] = strdup(buf.buf + strlen("refspec "));
		} else if (!strcmp(capname, "connect")) {
			data->connect = 1;
		} else if (!strcmp(buf.buf, "gitdir")) {
			struct strbuf gitdir = STRBUF_INIT;
			strbuf_addf(&gitdir, "gitdir %s\n", get_git_dir());
			sendline(data, &gitdir);
			strbuf_release(&gitdir);
		} else if (mandatory) {
			die("Unknown mandatory capability %s. This remote "
			    "helper probably needs newer version of Git.\n",
			    capname);
		}
	}
	if (refspecs) {
		int i;
		data->refspec_nr = refspec_nr;
		data->refspecs = parse_fetch_refspec(refspec_nr, refspecs);
		for (i = 0; i < refspec_nr; i++) {
			free((char *)refspecs[i]);
		}
		free(refspecs);
	}
	strbuf_release(&buf);
	if (debug)
		fprintf(stderr, "Debug: Capabilities complete.\n");
	return data->helper;
}

static int disconnect_helper(struct transport *transport)
{
	struct helper_data *data = transport->data;
	struct strbuf buf = STRBUF_INIT;

	if (data->helper) {
		if (debug)
			fprintf(stderr, "Debug: Disconnecting.\n");
		if (!data->no_disconnect_req) {
			strbuf_addf(&buf, "\n");
			sendline(data, &buf);
		}
		close(data->helper->in);
		close(data->helper->out);
		fclose(data->out);
		finish_command(data->helper);
		free((char *)data->helper->argv[0]);
		free(data->helper->argv);
		free(data->helper);
		data->helper = NULL;
	}
	return 0;
}

static const char *unsupported_options[] = {
	TRANS_OPT_UPLOADPACK,
	TRANS_OPT_RECEIVEPACK,
	TRANS_OPT_THIN,
	TRANS_OPT_KEEP
	};
static const char *boolean_options[] = {
	TRANS_OPT_THIN,
	TRANS_OPT_KEEP,
	TRANS_OPT_FOLLOWTAGS
	};

static int set_helper_option(struct transport *transport,
			  const char *name, const char *value)
{
	struct helper_data *data = transport->data;
	struct strbuf buf = STRBUF_INIT;
	int i, ret, is_bool = 0;

	get_helper(transport);

	if (!data->option)
		return 1;

	for (i = 0; i < ARRAY_SIZE(unsupported_options); i++) {
		if (!strcmp(name, unsupported_options[i]))
			return 1;
	}

	for (i = 0; i < ARRAY_SIZE(boolean_options); i++) {
		if (!strcmp(name, boolean_options[i])) {
			is_bool = 1;
			break;
		}
	}

	strbuf_addf(&buf, "option %s ", name);
	if (is_bool)
		strbuf_addstr(&buf, value ? "true" : "false");
	else
		quote_c_style(value, &buf, NULL, 0);
	strbuf_addch(&buf, '\n');

	xchgline(data, &buf);

	if (!strcmp(buf.buf, "ok"))
		ret = 0;
	else if (!prefixcmp(buf.buf, "error")) {
		ret = -1;
	} else if (!strcmp(buf.buf, "unsupported"))
		ret = 1;
	else {
		warning("%s unexpectedly said: '%s'", data->name, buf.buf);
		ret = 1;
	}
	strbuf_release(&buf);
	return ret;
}

static void standard_options(struct transport *t)
{
	char buf[16];
	int n;
	int v = t->verbose;

	set_helper_option(t, "progress", t->progress ? "true" : "false");

	n = snprintf(buf, sizeof(buf), "%d", v + 1);
	if (n >= sizeof(buf))
		die("impossibly large verbosity value");
	set_helper_option(t, "verbosity", buf);
}

static int release_helper(struct transport *transport)
{
	struct helper_data *data = transport->data;
	free_refspec(data->refspec_nr, data->refspecs);
	data->refspecs = NULL;
	disconnect_helper(transport);
	free(transport->data);
	return 0;
}

static int fetch_with_fetch(struct transport *transport,
			    int nr_heads, struct ref **to_fetch)
{
	struct helper_data *data = transport->data;
	int i;
	struct strbuf buf = STRBUF_INIT;

	standard_options(transport);

	for (i = 0; i < nr_heads; i++) {
		const struct ref *posn = to_fetch[i];
		if (posn->status & REF_STATUS_UPTODATE)
			continue;

		strbuf_addf(&buf, "fetch %s %s\n",
			    sha1_to_hex(posn->old_sha1), posn->name);
	}

	strbuf_addch(&buf, '\n');
	sendline(data, &buf);

	while (1) {
		recvline(data, &buf);

		if (!prefixcmp(buf.buf, "lock ")) {
			const char *name = buf.buf + 5;
			if (transport->pack_lockfile)
				warning("%s also locked %s", data->name, name);
			else
				transport->pack_lockfile = xstrdup(name);
		}
		else if (!buf.len)
			break;
		else
			warning("%s unexpectedly said: '%s'", data->name, buf.buf);
	}
	strbuf_release(&buf);
	return 0;
}

static int get_importer(struct transport *transport, struct child_process *fastimport)
{
	struct child_process *helper = get_helper(transport);
	memset(fastimport, 0, sizeof(*fastimport));
	fastimport->in = helper->out;
	fastimport->argv = xcalloc(5, sizeof(*fastimport->argv));
	fastimport->argv[0] = "fast-import";
	fastimport->argv[1] = "--quiet";

	fastimport->git_cmd = 1;
	return start_command(fastimport);
}

static int get_exporter(struct transport *transport,
			struct child_process *fastexport,
			const char *export_marks,
			const char *import_marks,
			struct string_list *revlist_args)
{
	struct child_process *helper = get_helper(transport);
	int argc = 0, i;
	memset(fastexport, 0, sizeof(*fastexport));

	/* we need to duplicate helper->in because we want to use it after
	 * fastexport is done with it. */
	fastexport->out = dup(helper->in);
	fastexport->argv = xcalloc(4 + revlist_args->nr, sizeof(*fastexport->argv));
	fastexport->argv[argc++] = "fast-export";
	if (export_marks)
		fastexport->argv[argc++] = export_marks;
	if (import_marks)
		fastexport->argv[argc++] = import_marks;

	for (i = 0; i < revlist_args->nr; i++)
		fastexport->argv[argc++] = revlist_args->items[i].string;

	fastexport->git_cmd = 1;
	return start_command(fastexport);
}

static int fetch_with_import(struct transport *transport,
			     int nr_heads, struct ref **to_fetch)
{
	struct child_process fastimport;
	struct helper_data *data = transport->data;
	int i;
	struct ref *posn;
	struct strbuf buf = STRBUF_INIT;

	get_helper(transport);

	if (get_importer(transport, &fastimport))
		die("Couldn't run fast-import");

	for (i = 0; i < nr_heads; i++) {
		posn = to_fetch[i];
		if (posn->status & REF_STATUS_UPTODATE)
			continue;

		strbuf_addf(&buf, "import %s\n", posn->name);
		sendline(data, &buf);
		strbuf_reset(&buf);
	}
	disconnect_helper(transport);
	finish_command(&fastimport);
	free(fastimport.argv);
	fastimport.argv = NULL;

	for (i = 0; i < nr_heads; i++) {
		char *private;
		posn = to_fetch[i];
		if (posn->status & REF_STATUS_UPTODATE)
			continue;
		if (data->refspecs)
			private = apply_refspecs(data->refspecs, data->refspec_nr, posn->name);
		else
			private = strdup(posn->name);
		read_ref(private, posn->old_sha1);
		free(private);
	}
	strbuf_release(&buf);
	return 0;
}

static int process_connect_service(struct transport *transport,
				   const char *name, const char *exec)
{
	struct helper_data *data = transport->data;
	struct strbuf cmdbuf = STRBUF_INIT;
	struct child_process *helper;
	int r, duped, ret = 0;
	FILE *input;

	helper = get_helper(transport);

	/*
	 * Yes, dup the pipe another time, as we need unbuffered version
	 * of input pipe as FILE*. fclose() closes the underlying fd and
	 * stream buffering only can be changed before first I/O operation
	 * on it.
	 */
	duped = dup(helper->out);
	if (duped < 0)
		die_errno("Can't dup helper output fd");
	input = xfdopen(duped, "r");
	setvbuf(input, NULL, _IONBF, 0);

	/*
	 * Handle --upload-pack and friends. This is fire and forget...
	 * just warn if it fails.
	 */
	if (strcmp(name, exec)) {
		r = set_helper_option(transport, "servpath", exec);
		if (r > 0)
			warning("Setting remote service path not supported by protocol.");
		else if (r < 0)
			warning("Invalid remote service path.");
	}

	if (data->connect)
		strbuf_addf(&cmdbuf, "connect %s\n", name);
	else
		goto exit;

	sendline(data, &cmdbuf);
	recvline_fh(input, &cmdbuf);
	if (!strcmp(cmdbuf.buf, "")) {
		data->no_disconnect_req = 1;
		if (debug)
			fprintf(stderr, "Debug: Smart transport connection "
				"ready.\n");
		ret = 1;
	} else if (!strcmp(cmdbuf.buf, "fallback")) {
		if (debug)
			fprintf(stderr, "Debug: Falling back to dumb "
				"transport.\n");
	} else
		die("Unknown response to connect: %s",
			cmdbuf.buf);

exit:
	fclose(input);
	return ret;
}

static int process_connect(struct transport *transport,
				     int for_push)
{
	struct helper_data *data = transport->data;
	const char *name;
	const char *exec;

	name = for_push ? "git-receive-pack" : "git-upload-pack";
	if (for_push)
		exec = data->transport_options.receivepack;
	else
		exec = data->transport_options.uploadpack;

	return process_connect_service(transport, name, exec);
}

static int connect_helper(struct transport *transport, const char *name,
		   const char *exec, int fd[2])
{
	struct helper_data *data = transport->data;

	/* Get_helper so connect is inited. */
	get_helper(transport);
	if (!data->connect)
		die("Operation not supported by protocol.");

	if (!process_connect_service(transport, name, exec))
		die("Can't connect to subservice %s.", name);

	fd[0] = data->helper->out;
	fd[1] = data->helper->in;
	return 0;
}

static int fetch(struct transport *transport,
		 int nr_heads, struct ref **to_fetch)
{
	struct helper_data *data = transport->data;
	int i, count;

	if (process_connect(transport, 0)) {
		do_take_over(transport);
		return transport->fetch(transport, nr_heads, to_fetch);
	}

	count = 0;
	for (i = 0; i < nr_heads; i++)
		if (!(to_fetch[i]->status & REF_STATUS_UPTODATE))
			count++;

	if (!count)
		return 0;

	if (data->fetch)
		return fetch_with_fetch(transport, nr_heads, to_fetch);

	if (data->import)
		return fetch_with_import(transport, nr_heads, to_fetch);

	return -1;
}

static int push_refs_with_push(struct transport *transport,
		struct ref *remote_refs, int flags)
{
	int force_all = flags & TRANSPORT_PUSH_FORCE;
	int mirror = flags & TRANSPORT_PUSH_MIRROR;
	struct helper_data *data = transport->data;
	struct strbuf buf = STRBUF_INIT;
	struct ref *ref;

	get_helper(transport);
	if (!data->push)
		return 1;

	for (ref = remote_refs; ref; ref = ref->next) {
		if (!ref->peer_ref && !mirror)
			continue;

		/* Check for statuses set by set_ref_status_for_push() */
		switch (ref->status) {
		case REF_STATUS_REJECT_NONFASTFORWARD:
		case REF_STATUS_UPTODATE:
			continue;
		default:
			; /* do nothing */
		}

		if (force_all)
			ref->force = 1;

		strbuf_addstr(&buf, "push ");
		if (!ref->deletion) {
			if (ref->force)
				strbuf_addch(&buf, '+');
			if (ref->peer_ref)
				strbuf_addstr(&buf, ref->peer_ref->name);
			else
				strbuf_addstr(&buf, sha1_to_hex(ref->new_sha1));
		}
		strbuf_addch(&buf, ':');
		strbuf_addstr(&buf, ref->name);
		strbuf_addch(&buf, '\n');
	}
	if (buf.len == 0)
		return 0;

	standard_options(transport);

	if (flags & TRANSPORT_PUSH_DRY_RUN) {
		if (set_helper_option(transport, "dry-run", "true") != 0)
			die("helper %s does not support dry-run", data->name);
	}

	strbuf_addch(&buf, '\n');
	sendline(data, &buf);

	ref = remote_refs;
	while (1) {
		char *refname, *msg;
		int status;

		recvline(data, &buf);
		if (!buf.len)
			break;

		if (!prefixcmp(buf.buf, "ok ")) {
			status = REF_STATUS_OK;
			refname = buf.buf + 3;
		} else if (!prefixcmp(buf.buf, "error ")) {
			status = REF_STATUS_REMOTE_REJECT;
			refname = buf.buf + 6;
		} else
			die("expected ok/error, helper said '%s'\n", buf.buf);

		msg = strchr(refname, ' ');
		if (msg) {
			struct strbuf msg_buf = STRBUF_INIT;
			const char *end;

			*msg++ = '\0';
			if (!unquote_c_style(&msg_buf, msg, &end))
				msg = strbuf_detach(&msg_buf, NULL);
			else
				msg = xstrdup(msg);
			strbuf_release(&msg_buf);

			if (!strcmp(msg, "no match")) {
				status = REF_STATUS_NONE;
				free(msg);
				msg = NULL;
			}
			else if (!strcmp(msg, "up to date")) {
				status = REF_STATUS_UPTODATE;
				free(msg);
				msg = NULL;
			}
			else if (!strcmp(msg, "non-fast forward")) {
				status = REF_STATUS_REJECT_NONFASTFORWARD;
				free(msg);
				msg = NULL;
			}
		}

		if (ref)
			ref = find_ref_by_name(ref, refname);
		if (!ref)
			ref = find_ref_by_name(remote_refs, refname);
		if (!ref) {
			warning("helper reported unexpected status of %s", refname);
			continue;
		}

		if (ref->status != REF_STATUS_NONE) {
			/*
			 * Earlier, the ref was marked not to be pushed, so ignore the ref
			 * status reported by the remote helper if the latter is 'no match'.
			 */
			if (status == REF_STATUS_NONE)
				continue;
		}

		ref->status = status;
		ref->remote_status = msg;
	}
	strbuf_release(&buf);
	return 0;
}

static int push_refs_with_export(struct transport *transport,
		struct ref *remote_refs, int flags)
{
	struct ref *ref;
	struct child_process *helper, exporter;
	struct helper_data *data = transport->data;
	char *export_marks = NULL, *import_marks = NULL;
	struct string_list revlist_args = STRING_LIST_INIT_NODUP;
	struct strbuf buf = STRBUF_INIT;

	helper = get_helper(transport);

	write_constant(helper->in, "export\n");

	recvline(data, &buf);
	if (debug)
		fprintf(stderr, "Debug: Got export_marks '%s'\n", buf.buf);
	if (buf.len) {
		struct strbuf arg = STRBUF_INIT;
		strbuf_addstr(&arg, "--export-marks=");
		strbuf_addbuf(&arg, &buf);
		export_marks = strbuf_detach(&arg, NULL);
	}

	recvline(data, &buf);
	if (debug)
		fprintf(stderr, "Debug: Got import_marks '%s'\n", buf.buf);
	if (buf.len) {
		struct strbuf arg = STRBUF_INIT;
		strbuf_addstr(&arg, "--import-marks=");
		strbuf_addbuf(&arg, &buf);
		import_marks = strbuf_detach(&arg, NULL);
	}

	strbuf_reset(&buf);

	for (ref = remote_refs; ref; ref = ref->next) {
		char *private;
		unsigned char sha1[20];

		if (!data->refspecs)
			continue;
		private = apply_refspecs(data->refspecs, data->refspec_nr, ref->name);
		if (private && !get_sha1(private, sha1)) {
			strbuf_addf(&buf, "^%s", private);
			string_list_append(&revlist_args, strbuf_detach(&buf, NULL));
		}

		string_list_append(&revlist_args, ref->name);

	}

	if (get_exporter(transport, &exporter,
			 export_marks, import_marks, &revlist_args))
		die("Couldn't run fast-export");

	data->no_disconnect_req = 1;
	finish_command(&exporter);
	disconnect_helper(transport);
	return 0;
}

static int push_refs(struct transport *transport,
		struct ref *remote_refs, int flags)
{
	struct helper_data *data = transport->data;

	if (process_connect(transport, 1)) {
		do_take_over(transport);
		return transport->push_refs(transport, remote_refs, flags);
	}

	if (!remote_refs) {
		fprintf(stderr, "No refs in common and none specified; doing nothing.\n"
			"Perhaps you should specify a branch such as 'master'.\n");
		return 0;
	}

	if (data->push)
		return push_refs_with_push(transport, remote_refs, flags);

	if (data->export)
		return push_refs_with_export(transport, remote_refs, flags);

	return -1;
}


static int has_attribute(const char *attrs, const char *attr) {
	int len;
	if (!attrs)
		return 0;

	len = strlen(attr);
	for (;;) {
		const char *space = strchrnul(attrs, ' ');
		if (len == space - attrs && !strncmp(attrs, attr, len))
			return 1;
		if (!*space)
			return 0;
		attrs = space + 1;
	}
}

static struct ref *get_refs_list(struct transport *transport, int for_push)
{
	struct helper_data *data = transport->data;
	struct child_process *helper;
	struct ref *ret = NULL;
	struct ref **tail = &ret;
	struct ref *posn;
	struct strbuf buf = STRBUF_INIT;

	helper = get_helper(transport);

	if (process_connect(transport, for_push)) {
		do_take_over(transport);
		return transport->get_refs_list(transport, for_push);
	}

	if (data->push && for_push)
		write_str_in_full(helper->in, "list for-push\n");
	else
		write_str_in_full(helper->in, "list\n");

	while (1) {
		char *eov, *eon;
		recvline(data, &buf);

		if (!*buf.buf)
			break;

		eov = strchr(buf.buf, ' ');
		if (!eov)
			die("Malformed response in ref list: %s", buf.buf);
		eon = strchr(eov + 1, ' ');
		*eov = '\0';
		if (eon)
			*eon = '\0';
		*tail = alloc_ref(eov + 1);
		if (buf.buf[0] == '@')
			(*tail)->symref = xstrdup(buf.buf + 1);
		else if (buf.buf[0] != '?')
			get_sha1_hex(buf.buf, (*tail)->old_sha1);
		if (eon) {
			if (has_attribute(eon + 1, "unchanged")) {
				(*tail)->status |= REF_STATUS_UPTODATE;
				read_ref((*tail)->name, (*tail)->old_sha1);
			}
		}
		tail = &((*tail)->next);
	}
	if (debug)
		fprintf(stderr, "Debug: Read ref listing.\n");
	strbuf_release(&buf);

	for (posn = ret; posn; posn = posn->next)
		resolve_remote_symref(posn, ret);

	return ret;
}

int transport_helper_init(struct transport *transport, const char *name)
{
	struct helper_data *data = xcalloc(sizeof(*data), 1);
	data->name = name;

	if (getenv("GIT_TRANSPORT_HELPER_DEBUG"))
		debug = 1;

	transport->data = data;
	transport->set_option = set_helper_option;
	transport->get_refs_list = get_refs_list;
	transport->fetch = fetch;
	transport->push_refs = push_refs;
	transport->disconnect = release_helper;
	transport->connect = connect_helper;
	transport->smart_options = &(data->transport_options);
	return 0;
}

/*
 * Linux pipes can buffer 65536 bytes at once (and most platforms can
 * buffer less), so attempt reads and writes with up to that size.
 */
#define BUFFERSIZE 65536
/* This should be enough to hold debugging message. */
#define PBUFFERSIZE 8192

/* Print bidirectional transfer loop debug message. */
static void transfer_debug(const char *fmt, ...)
{
	va_list args;
	char msgbuf[PBUFFERSIZE];
	static int debug_enabled = -1;

	if (debug_enabled < 0)
		debug_enabled = getenv("GIT_TRANSLOOP_DEBUG") ? 1 : 0;
	if (!debug_enabled)
		return;

	va_start(args, fmt);
	vsnprintf(msgbuf, PBUFFERSIZE, fmt, args);
	va_end(args);
	fprintf(stderr, "Transfer loop debugging: %s\n", msgbuf);
}

/* Stream state: More data may be coming in this direction. */
#define SSTATE_TRANSFERING 0
/*
 * Stream state: No more data coming in this direction, flushing rest of
 * data.
 */
#define SSTATE_FLUSHING 1
/* Stream state: Transfer in this direction finished. */
#define SSTATE_FINISHED 2

#define STATE_NEEDS_READING(state) ((state) <= SSTATE_TRANSFERING)
#define STATE_NEEDS_WRITING(state) ((state) <= SSTATE_FLUSHING)
#define STATE_NEEDS_CLOSING(state) ((state) == SSTATE_FLUSHING)

/* Unidirectional transfer. */
struct unidirectional_transfer {
	/* Source */
	int src;
	/* Destination */
	int dest;
	/* Is source socket? */
	int src_is_sock;
	/* Is destination socket? */
	int dest_is_sock;
	/* Transfer state (TRANSFERING/FLUSHING/FINISHED) */
	int state;
	/* Buffer. */
	char buf[BUFFERSIZE];
	/* Buffer used. */
	size_t bufuse;
	/* Name of source. */
	const char *src_name;
	/* Name of destination. */
	const char *dest_name;
};

/* Closes the target (for writing) if transfer has finished. */
static void udt_close_if_finished(struct unidirectional_transfer *t)
{
	if (STATE_NEEDS_CLOSING(t->state) && !t->bufuse) {
		t->state = SSTATE_FINISHED;
		if (t->dest_is_sock)
			shutdown(t->dest, SHUT_WR);
		else
			close(t->dest);
		transfer_debug("Closed %s.", t->dest_name);
	}
}

/*
 * Tries to read read data from source into buffer. If buffer is full,
 * no data is read. Returns 0 on success, -1 on error.
 */
static int udt_do_read(struct unidirectional_transfer *t)
{
	ssize_t bytes;

	if (t->bufuse == BUFFERSIZE)
		return 0;	/* No space for more. */

	transfer_debug("%s is readable", t->src_name);
	bytes = read(t->src, t->buf + t->bufuse, BUFFERSIZE - t->bufuse);
	if (bytes < 0 && errno != EWOULDBLOCK && errno != EAGAIN &&
		errno != EINTR) {
		error("read(%s) failed: %s", t->src_name, strerror(errno));
		return -1;
	} else if (bytes == 0) {
		transfer_debug("%s EOF (with %i bytes in buffer)",
			t->src_name, t->bufuse);
		t->state = SSTATE_FLUSHING;
	} else if (bytes > 0) {
		t->bufuse += bytes;
		transfer_debug("Read %i bytes from %s (buffer now at %i)",
			(int)bytes, t->src_name, (int)t->bufuse);
	}
	return 0;
}

/* Tries to write data from buffer into destination. If buffer is empty,
 * no data is written. Returns 0 on success, -1 on error.
 */
static int udt_do_write(struct unidirectional_transfer *t)
{
	ssize_t bytes;

	if (t->bufuse == 0)
		return 0;	/* Nothing to write. */

	transfer_debug("%s is writable", t->dest_name);
	bytes = write(t->dest, t->buf, t->bufuse);
	if (bytes < 0 && errno != EWOULDBLOCK && errno != EAGAIN &&
		errno != EINTR) {
		error("write(%s) failed: %s", t->dest_name, strerror(errno));
		return -1;
	} else if (bytes > 0) {
		t->bufuse -= bytes;
		if (t->bufuse)
			memmove(t->buf, t->buf + bytes, t->bufuse);
		transfer_debug("Wrote %i bytes to %s (buffer now at %i)",
			(int)bytes, t->dest_name, (int)t->bufuse);
	}
	return 0;
}


/* State of bidirectional transfer loop. */
struct bidirectional_transfer_state {
	/* Direction from program to git. */
	struct unidirectional_transfer ptg;
	/* Direction from git to program. */
	struct unidirectional_transfer gtp;
};

static void *udt_copy_task_routine(void *udt)
{
	struct unidirectional_transfer *t = (struct unidirectional_transfer *)udt;
	while (t->state != SSTATE_FINISHED) {
		if (STATE_NEEDS_READING(t->state))
			if (udt_do_read(t))
				return NULL;
		if (STATE_NEEDS_WRITING(t->state))
			if (udt_do_write(t))
				return NULL;
		if (STATE_NEEDS_CLOSING(t->state))
			udt_close_if_finished(t);
	}
	return udt;	/* Just some non-NULL value. */
}

#ifndef NO_PTHREADS

/*
 * Join thread, with apporiate errors on failure. Name is name for the
 * thread (for error messages). Returns 0 on success, 1 on failure.
 */
static int tloop_join(pthread_t thread, const char *name)
{
	int err;
	void *tret;
	err = pthread_join(thread, &tret);
	if (!tret) {
		error("%s thread failed", name);
		return 1;
	}
	if (err) {
		error("%s thread failed to join: %s", name, strerror(err));
		return 1;
	}
	return 0;
}

/*
 * Spawn the transfer tasks and then wait for them. Returns 0 on success,
 * -1 on failure.
 */
static int tloop_spawnwait_tasks(struct bidirectional_transfer_state *s)
{
	pthread_t gtp_thread;
	pthread_t ptg_thread;
	int err;
	int ret = 0;
	err = pthread_create(&gtp_thread, NULL, udt_copy_task_routine,
		&s->gtp);
	if (err)
		die("Can't start thread for copying data: %s", strerror(err));
	err = pthread_create(&ptg_thread, NULL, udt_copy_task_routine,
		&s->ptg);
	if (err)
		die("Can't start thread for copying data: %s", strerror(err));

	ret |= tloop_join(gtp_thread, "Git to program copy");
	ret |= tloop_join(ptg_thread, "Program to git copy");
	return ret;
}
#else

/* Close the source and target (for writing) for transfer. */
static void udt_kill_transfer(struct unidirectional_transfer *t)
{
	t->state = SSTATE_FINISHED;
	/*
	 * Socket read end left open isn't a disaster if nobody
	 * attempts to read from it (mingw compat headers do not
	 * have SHUT_RD)...
	 *
	 * We can't fully close the socket since otherwise gtp
	 * task would first close the socket it sends data to
	 * while closing the ptg file descriptors.
	 */
	if (!t->src_is_sock)
		close(t->src);
	if (t->dest_is_sock)
		shutdown(t->dest, SHUT_WR);
	else
		close(t->dest);
}

/*
 * Join process, with apporiate errors on failure. Name is name for the
 * process (for error messages). Returns 0 on success, 1 on failure.
 */
static int tloop_join(pid_t pid, const char *name)
{
	int tret;
	if (waitpid(pid, &tret, 0) < 0) {
		error("%s process failed to wait: %s", name, strerror(errno));
		return 1;
	}
	if (!WIFEXITED(tret) || WEXITSTATUS(tret)) {
		error("%s process failed", name);
		return 1;
	}
	return 0;
}

/*
 * Spawn the transfer tasks and then wait for them. Returns 0 on success,
 * -1 on failure.
 */
static int tloop_spawnwait_tasks(struct bidirectional_transfer_state *s)
{
	pid_t pid1, pid2;
	int ret = 0;

	/* Fork thread #1: git to program. */
	pid1 = fork();
	if (pid1 < 0)
		die_errno("Can't start thread for copying data");
	else if (pid1 == 0) {
		udt_kill_transfer(&s->ptg);
		exit(udt_copy_task_routine(&s->gtp) ? 0 : 1);
	}

	/* Fork thread #2: program to git. */
	pid2 = fork();
	if (pid2 < 0)
		die_errno("Can't start thread for copying data");
	else if (pid2 == 0) {
		udt_kill_transfer(&s->gtp);
		exit(udt_copy_task_routine(&s->ptg) ? 0 : 1);
	}

	/*
	 * Close both streams in parent as to not interfere with
	 * end of file detection and wait for both tasks to finish.
	 */
	udt_kill_transfer(&s->gtp);
	udt_kill_transfer(&s->ptg);
	ret |= tloop_join(pid1, "Git to program copy");
	ret |= tloop_join(pid2, "Program to git copy");
	return ret;
}
#endif

/*
 * Copies data from stdin to output and from input to stdout simultaneously.
 * Additionally filtering through given filter. If filter is NULL, uses
 * identity filter.
 */
int bidirectional_transfer_loop(int input, int output)
{
	struct bidirectional_transfer_state state;

	/* Fill the state fields. */
	state.ptg.src = input;
	state.ptg.dest = 1;
	state.ptg.src_is_sock = (input == output);
	state.ptg.dest_is_sock = 0;
	state.ptg.state = SSTATE_TRANSFERING;
	state.ptg.bufuse = 0;
	state.ptg.src_name = "remote input";
	state.ptg.dest_name = "stdout";

	state.gtp.src = 0;
	state.gtp.dest = output;
	state.gtp.src_is_sock = 0;
	state.gtp.dest_is_sock = (input == output);
	state.gtp.state = SSTATE_TRANSFERING;
	state.gtp.bufuse = 0;
	state.gtp.src_name = "stdin";
	state.gtp.dest_name = "remote output";

	return tloop_spawnwait_tasks(&state);
}
