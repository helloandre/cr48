# Copyright 2008 Canonical Ltd.

# This file is part of lazr.restfulclient.
#
# lazr.restfulclient is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# lazr.restfulclient is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with lazr.restfulclient.  If not, see
# <http://www.gnu.org/licenses/>.

"""Browser object to make requests of lazr.restful web services.

The `Browser` class does some massage of HTTP requests and responses,
and handles custom caches. It is not part of the public
lazr.restfulclient API. (But maybe it should be?)
"""

__metaclass__ = type
__all__ = [
    'Browser',
    'RestfulHttp',
    ]


import atexit
import gzip
import shutil
import tempfile
# Import sleep directly into the module so we can monkey-patch it
# during a test.
from time import sleep
from httplib2 import (
    FailedToDecompressContent, FileCache, Http, urlnorm)
import simplejson
from cStringIO import StringIO
import zlib

from urllib import urlencode
from wadllib.application import Application
from lazr.uri import URI
from errors import HTTPError
from _json import DatetimeJSONEncoder

# A drop-in replacement for httplib2's safename.
from httplib2 import _md5, re_url_scheme, re_slash
def safename(filename):
    """Return a filename suitable for the cache.

    Strips dangerous and common characters to create a filename we
    can use to store the cache in.
    """

    try:
        if re_url_scheme.match(filename):
            if isinstance(filename,str):
                filename = filename.decode('utf-8')
                filename = filename.encode('idna')
            else:
                filename = filename.encode('idna')
    except UnicodeError:
        pass
    if isinstance(filename,unicode):
        filename=filename.encode('utf-8')
    filemd5 = _md5(filename).hexdigest()
    filename = re_url_scheme.sub("", filename)
    filename = re_slash.sub(",", filename)

    # This is the part that we changed. In stock httplib2, the
    # filename is trimmed if it's longer than 200 characters, and then
    # a comma and a 32-character md5 sum are appended. This causes
    # problems on eCryptfs filesystems, where the maximum safe
    # filename length is closer to 143 characters.
    #
    # We take a (user-hackable) maximum filename length from
    # RestfulHttp and subtract 33 characters to make room for the comma
    # and the md5 sum.
    #
    # See:
    #  http://code.google.com/p/httplib2/issues/detail?id=92
    #  https://bugs.launchpad.net/bugs/344878
    #  https://bugs.launchpad.net/bugs/545197
    maximum_filename_length = RestfulHttp.maximum_cache_filename_length
    maximum_length_before_md5_sum = maximum_filename_length - 32 - 1
    if len(filename) > maximum_length_before_md5_sum:
        filename=filename[:maximum_length_before_md5_sum]
    return ",".join((filename, filemd5))


class RestfulHttp(Http):
    """An Http subclass with some custom behavior.

    This Http client uses the TE header instead of the Accept-Encoding
    header to ask for compressed representations. It also knows how to
    react when its cache is a MultipleRepresentationCache.
    """

    maximum_cache_filename_length = 143

    def __init__(self, authorizer=None, cache=None, timeout=None,
                 proxy_info=None):
        super(RestfulHttp, self).__init__(cache, timeout, proxy_info)
        self.authorizer = authorizer
        if self.authorizer is not None:
            self.authorizer.authorizeSession(self)

    def _request(self, conn, host, absolute_uri, request_uri, method, body,
                 headers, redirections, cachekey):
        """Use the authorizer to authorize an outgoing request."""
        if headers.has_key('authorization'):
            # There's an authorization header left over from a
            # previous request that resulted in a redirect. Resources
            # protected by OAuth or HTTP Digest must send a distinct
            # Authorization header with each request, to prevent
            # playback attacks. Remove the Authorization header and
            # start again.
            del headers['authorization']
        if self.authorizer is not None:
            self.authorizer.authorizeRequest(
                absolute_uri, method, body, headers)
        return super(RestfulHttp, self)._request(
            conn, host, absolute_uri, request_uri, method, body, headers,
            redirections, cachekey)

    def _getCachedHeader(self, uri, header):
        """Retrieve a cached value for an HTTP header."""
        if isinstance(self.cache, MultipleRepresentationCache):
            return self.cache._getCachedHeader(uri, header)
        return None


class MultipleRepresentationCache(FileCache):
    """A cache that can hold different representations of the same resource.

    If a resource has two representations with two media types,
    FileCache will only store the most recently fetched
    representation. This cache can keep track of multiple
    representations of the same resource.

    This class works on the assumption that outside calling code sets
    an instance's request_media_type attribute to the value of the
    'Accept' header before initiating the request.

    This class is very much not thread-safe, but FileCache isn't
    thread-safe anyway.
    """
    def __init__(self, cache):
        """Tell FileCache to call append_media_type when generating keys."""
        super(MultipleRepresentationCache, self).__init__(
            cache, self.append_media_type)
        self.request_media_type = None

    def append_media_type(self, key):
        """Append the request media type to the cache key.

        This ensures that representations of the same resource will be
        cached separately, so long as they're served as different
        media types.
        """
        if self.request_media_type is not None:
            key = key + '-' + self.request_media_type
        return safename(key)


    def _getCachedHeader(self, uri, header):
        """Retrieve a cached value for an HTTP header."""
        (scheme, authority, request_uri, cachekey) = urlnorm(uri)
        cached_value = self.get(cachekey)
        header_start = header + ':'
        if cached_value is not None:
            for line in StringIO(cached_value):
                if line.startswith(header_start):
                    return line[len(header_start):].strip()
        return None


class Browser:
    """A class for making calls to lazr.restful web services."""

    NOT_MODIFIED = object()
    MAX_RETRIES = 6

    def __init__(self, service_root, credentials, cache=None, timeout=None,
                 proxy_info=None, user_agent=None, max_retries=MAX_RETRIES):
        """Initialize, possibly creating a cache.

        If no cache is provided, a temporary directory will be used as
        a cache. The temporary directory will be automatically removed
        when the Python process exits.
        """
        if cache is None:
            cache = tempfile.mkdtemp()
            atexit.register(shutil.rmtree, cache)
        if isinstance(cache, basestring):
            cache = MultipleRepresentationCache(cache)
        self._connection = service_root.httpFactory(
            credentials, cache, timeout, proxy_info)
        self.user_agent = user_agent
        self.max_retries = max_retries

    def _request_and_retry(self, url, method, body, headers):
        for retry_count in range(0, self.max_retries+1):
            response, content = self._connection.request(
                url, method=method, body=body, headers=headers)
            if (response.status in [502, 503]
                and retry_count < self.max_retries):
                # The server returned a 502 or 503. Sleep for 0, 1, 2,
                # 4, 8, 16, ... seconds and try again.
                sleep_for = int(2**(retry_count-1))
                sleep(sleep_for)
            else:
                break
        # Either the request succeeded or we gave up.
        return response, content

    def _request(self, url, data=None, method='GET',
                 media_type='application/json', extra_headers=None):
        """Create an authenticated request object."""
        # If the user is trying to get data that has been redacted,
        # give a helpful message.
        if url == "tag:launchpad.net:2008:redacted":
            raise ValueError("You tried to access a resource that you "
                             "don't have the server-side permission to see.")

        # Add extra headers for the request.
        headers = {'Accept' : media_type}
        if self.user_agent is not None:
            headers['User-Agent'] = self.user_agent
        if isinstance(self._connection.cache, MultipleRepresentationCache):
            self._connection.cache.request_media_type = media_type
        if extra_headers is not None:
            headers.update(extra_headers)
        # Make the request.
        response, content = self._request_and_retry(
            str(url), method=method, body=data, headers=headers)
        if response.status == 304:
            # The resource didn't change.
            if content == '':
                if ('If-None-Match' in headers
                    or 'If-Modified-Since' in headers):
                    # The caller made a conditional request, and the
                    # condition failed. Rather than send an empty
                    # representation, which might be misinterpreted,
                    # send a special object that will let the calling code know
                    # that the resource was not modified.
                    return response, self.NOT_MODIFIED
                else:
                    # The caller didn't make a conditional request,
                    # but the response code is 304 and there's no
                    # content. The only way to handle this is to raise
                    # an error.
                    raise HTTPError(response, content)
            else:
                # XXX leonardr 2010/04/12 bug=httplib2#97
                #
                # Why is this check here? Why would there ever be any
                # content when the response code is 304? It's because of
                # an httplib2 bug that sometimes sets a 304 response
                # code when caching retrieved documents. When the
                # cached document is retrieved, we get a 304 response
                # code and a full representation.
                #
                # Since the cache lookup succeeded, the 'real'
                # response code is 200. This code undoes the bad
                # behavior in httplib2.
                response.status = 200
            return response, content
        # Turn non-2xx responses into exceptions.
        if response.status // 100 != 2:
            raise HTTPError(response, content)
        return response, content

    def get(self, resource_or_uri, headers=None, return_response=False):
        """GET a representation of the given resource or URI."""
        if isinstance(resource_or_uri, (basestring, URI)):
            url = resource_or_uri
        else:
            method = resource_or_uri.get_method('get')
            url = method.build_request_url()
        response, content = self._request(url, extra_headers=headers)
        if return_response:
            return (response, content)
        return content

    def get_wadl_application(self, url):
        """GET a WADL representation of the resource at the requested url."""
        wadl_type = 'application/vnd.sun.wadl+xml'
        response, content = self._request(url, media_type=wadl_type)
        return Application(str(url), content)

    def post(self, url, method_name, **kws):
        """POST a request to the web service."""
        kws['ws.op'] = method_name
        data = urlencode(kws)
        return self._request(url, data, 'POST')

    def put(self, url, representation, media_type, headers=None):
        """PUT the given representation to the URL."""
        extra_headers = {'Content-Type': media_type}
        if headers is not None:
            extra_headers.update(headers)
        return self._request(
            url, representation, 'PUT', extra_headers=extra_headers)

    def delete(self, url):
        """DELETE the resource at the given URL."""
        self._request(url, method='DELETE')
        return None

    def patch(self, url, representation, headers=None):
        """PATCH the object at url with the updated representation."""
        extra_headers = {'Content-Type': 'application/json'}
        if headers is not None:
            extra_headers.update(headers)
        # httplib2 doesn't know about the PATCH method, so we need to
        # do some work ourselves. Pull any cached value of "ETag" out
        # and use it as the value for "If-Match".
        cached_etag = self._connection._getCachedHeader(str(url), 'etag')
        if cached_etag is not None and not self._connection.ignore_etag:
            # http://www.w3.org/1999/04/Editing/
            headers['If-Match'] = cached_etag

        return self._request(
            url, simplejson.dumps(representation, cls=DatetimeJSONEncoder),
            'PATCH', extra_headers=extra_headers)
