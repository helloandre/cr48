# hgweb/server.py - The standalone hg web server.
#
# Copyright 21 May 2005 - (c) 2005 Jake Edge <jake@edge2.net>
# Copyright 2005-2007 Matt Mackall <mpm@selenic.com>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

import os, sys, errno, urllib, BaseHTTPServer, socket, SocketServer, traceback
from mercurial import util, error
from mercurial.i18n import _

def _splitURI(uri):
    """ Return path and query splited from uri

    Just like CGI environment, the path is unquoted, the query is
    not.
    """
    if '?' in uri:
        path, query = uri.split('?', 1)
    else:
        path, query = uri, ''
    return urllib.unquote(path), query

class _error_logger(object):
    def __init__(self, handler):
        self.handler = handler
    def flush(self):
        pass
    def write(self, str):
        self.writelines(str.split('\n'))
    def writelines(self, seq):
        for msg in seq:
            self.handler.log_error("HG error:  %s", msg)

class _httprequesthandler(BaseHTTPServer.BaseHTTPRequestHandler):

    url_scheme = 'http'

    @staticmethod
    def preparehttpserver(httpserver, ssl_cert):
        """Prepare .socket of new HTTPServer instance"""
        pass

    def __init__(self, *args, **kargs):
        self.protocol_version = 'HTTP/1.1'
        BaseHTTPServer.BaseHTTPRequestHandler.__init__(self, *args, **kargs)

    def _log_any(self, fp, format, *args):
        fp.write("%s - - [%s] %s\n" % (self.client_address[0],
                                       self.log_date_time_string(),
                                       format % args))
        fp.flush()

    def log_error(self, format, *args):
        self._log_any(self.server.errorlog, format, *args)

    def log_message(self, format, *args):
        self._log_any(self.server.accesslog, format, *args)

    def do_write(self):
        try:
            self.do_hgweb()
        except socket.error, inst:
            if inst[0] != errno.EPIPE:
                raise

    def do_POST(self):
        try:
            self.do_write()
        except StandardError:
            self._start_response("500 Internal Server Error", [])
            self._write("Internal Server Error")
            tb = "".join(traceback.format_exception(*sys.exc_info()))
            self.log_error("Exception happened during processing "
                           "request '%s':\n%s", self.path, tb)

    def do_GET(self):
        self.do_POST()

    def do_hgweb(self):
        path, query = _splitURI(self.path)

        env = {}
        env['GATEWAY_INTERFACE'] = 'CGI/1.1'
        env['REQUEST_METHOD'] = self.command
        env['SERVER_NAME'] = self.server.server_name
        env['SERVER_PORT'] = str(self.server.server_port)
        env['REQUEST_URI'] = self.path
        env['SCRIPT_NAME'] = self.server.prefix
        env['PATH_INFO'] = path[len(self.server.prefix):]
        env['REMOTE_HOST'] = self.client_address[0]
        env['REMOTE_ADDR'] = self.client_address[0]
        if query:
            env['QUERY_STRING'] = query

        if self.headers.typeheader is None:
            env['CONTENT_TYPE'] = self.headers.type
        else:
            env['CONTENT_TYPE'] = self.headers.typeheader
        length = self.headers.getheader('content-length')
        if length:
            env['CONTENT_LENGTH'] = length
        for header in [h for h in self.headers.keys()
                       if h not in ('content-type', 'content-length')]:
            hkey = 'HTTP_' + header.replace('-', '_').upper()
            hval = self.headers.getheader(header)
            hval = hval.replace('\n', '').strip()
            if hval:
                env[hkey] = hval
        env['SERVER_PROTOCOL'] = self.request_version
        env['wsgi.version'] = (1, 0)
        env['wsgi.url_scheme'] = self.url_scheme
        env['wsgi.input'] = self.rfile
        env['wsgi.errors'] = _error_logger(self)
        env['wsgi.multithread'] = isinstance(self.server,
                                             SocketServer.ThreadingMixIn)
        env['wsgi.multiprocess'] = isinstance(self.server,
                                              SocketServer.ForkingMixIn)
        env['wsgi.run_once'] = 0

        self.close_connection = True
        self.saved_status = None
        self.saved_headers = []
        self.sent_headers = False
        self.length = None
        for chunk in self.server.application(env, self._start_response):
            self._write(chunk)

    def send_headers(self):
        if not self.saved_status:
            raise AssertionError("Sending headers before "
                                 "start_response() called")
        saved_status = self.saved_status.split(None, 1)
        saved_status[0] = int(saved_status[0])
        self.send_response(*saved_status)
        should_close = True
        for h in self.saved_headers:
            self.send_header(*h)
            if h[0].lower() == 'content-length':
                should_close = False
                self.length = int(h[1])
        # The value of the Connection header is a list of case-insensitive
        # tokens separated by commas and optional whitespace.
        if 'close' in [token.strip().lower() for token in
                       self.headers.get('connection', '').split(',')]:
            should_close = True
        if should_close:
            self.send_header('Connection', 'close')
        self.close_connection = should_close
        self.end_headers()
        self.sent_headers = True

    def _start_response(self, http_status, headers, exc_info=None):
        code, msg = http_status.split(None, 1)
        code = int(code)
        self.saved_status = http_status
        bad_headers = ('connection', 'transfer-encoding')
        self.saved_headers = [h for h in headers
                              if h[0].lower() not in bad_headers]
        return self._write

    def _write(self, data):
        if not self.saved_status:
            raise AssertionError("data written before start_response() called")
        elif not self.sent_headers:
            self.send_headers()
        if self.length is not None:
            if len(data) > self.length:
                raise AssertionError("Content-length header sent, but more "
                                     "bytes than specified are being written.")
            self.length = self.length - len(data)
        self.wfile.write(data)
        self.wfile.flush()

class _httprequesthandleropenssl(_httprequesthandler):
    """HTTPS handler based on pyOpenSSL"""

    url_scheme = 'https'

    @staticmethod
    def preparehttpserver(httpserver, ssl_cert):
        try:
            import OpenSSL
            OpenSSL.SSL.Context
        except ImportError:
            raise util.Abort(_("SSL support is unavailable"))
        ctx = OpenSSL.SSL.Context(OpenSSL.SSL.SSLv23_METHOD)
        ctx.use_privatekey_file(ssl_cert)
        ctx.use_certificate_file(ssl_cert)
        sock = socket.socket(httpserver.address_family, httpserver.socket_type)
        httpserver.socket = OpenSSL.SSL.Connection(ctx, sock)
        httpserver.server_bind()
        httpserver.server_activate()

    def setup(self):
        self.connection = self.request
        self.rfile = socket._fileobject(self.request, "rb", self.rbufsize)
        self.wfile = socket._fileobject(self.request, "wb", self.wbufsize)

    def do_write(self):
        import OpenSSL
        try:
            _httprequesthandler.do_write(self)
        except OpenSSL.SSL.SysCallError, inst:
            if inst.args[0] != errno.EPIPE:
                raise

    def handle_one_request(self):
        import OpenSSL
        try:
            _httprequesthandler.handle_one_request(self)
        except (OpenSSL.SSL.SysCallError, OpenSSL.SSL.ZeroReturnError):
            self.close_connection = True
            pass

class _httprequesthandlerssl(_httprequesthandler):
    """HTTPS handler based on Pythons ssl module (introduced in 2.6)"""

    url_scheme = 'https'

    @staticmethod
    def preparehttpserver(httpserver, ssl_cert):
        try:
            import ssl
            ssl.wrap_socket
        except ImportError:
            raise util.Abort(_("SSL support is unavailable"))
        httpserver.socket = ssl.wrap_socket(httpserver.socket, server_side=True,
            certfile=ssl_cert, ssl_version=ssl.PROTOCOL_SSLv23)

    def setup(self):
        self.connection = self.request
        self.rfile = socket._fileobject(self.request, "rb", self.rbufsize)
        self.wfile = socket._fileobject(self.request, "wb", self.wbufsize)

try:
    from threading import activeCount
    _mixin = SocketServer.ThreadingMixIn
except ImportError:
    if hasattr(os, "fork"):
        _mixin = SocketServer.ForkingMixIn
    else:
        class _mixin:
            pass

def openlog(opt, default):
    if opt and opt != '-':
        return open(opt, 'a')
    return default

class MercurialHTTPServer(object, _mixin, BaseHTTPServer.HTTPServer):

    # SO_REUSEADDR has broken semantics on windows
    if os.name == 'nt':
        allow_reuse_address = 0

    def __init__(self, ui, app, addr, handler, **kwargs):
        BaseHTTPServer.HTTPServer.__init__(self, addr, handler, **kwargs)
        self.daemon_threads = True
        self.application = app

        handler.preparehttpserver(self, ui.config('web', 'certificate'))

        prefix = ui.config('web', 'prefix', '')
        if prefix:
            prefix = '/' + prefix.strip('/')
        self.prefix = prefix

        alog = openlog(ui.config('web', 'accesslog', '-'), sys.stdout)
        elog = openlog(ui.config('web', 'errorlog', '-'), sys.stderr)
        self.accesslog = alog
        self.errorlog = elog

        self.addr, self.port = self.socket.getsockname()[0:2]
        self.fqaddr = socket.getfqdn(addr[0])

class IPv6HTTPServer(MercurialHTTPServer):
    address_family = getattr(socket, 'AF_INET6', None)
    def __init__(self, *args, **kwargs):
        if self.address_family is None:
            raise error.RepoError(_('IPv6 is not available on this system'))
        super(IPv6HTTPServer, self).__init__(*args, **kwargs)

def create_server(ui, app):

    if ui.config('web', 'certificate'):
        if sys.version_info >= (2, 6):
            handler = _httprequesthandlerssl
        else:
            handler = _httprequesthandleropenssl
    else:
        handler = _httprequesthandler

    if ui.configbool('web', 'ipv6'):
        cls = IPv6HTTPServer
    else:
        cls = MercurialHTTPServer

    # ugly hack due to python issue5853 (for threaded use)
    import mimetypes; mimetypes.init()

    address = ui.config('web', 'address', '')
    port = util.getport(ui.config('web', 'port', 8000))
    try:
        return cls(ui, app, (address, port), handler)
    except socket.error, inst:
        raise util.Abort(_("cannot start server at '%s:%d': %s")
                         % (address, port, inst.args[1]))
