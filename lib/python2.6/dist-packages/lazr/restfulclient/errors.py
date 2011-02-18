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

"""lazr.restfulclient errors."""

__metaclass__ = type
__all__ = [
    'CredentialsError',
    'CredentialsFileError',
    'HTTPError',
    'RestfulError',
    'ResponseError',
    'UnexpectedResponseError',
    ]


class RestfulError(Exception):
    """Base error for the lazr.restfulclient API library."""


class CredentialsError(RestfulError):
    """Base credentials/authentication error."""


class CredentialsFileError(CredentialsError):
    """Error in credentials file."""


class ResponseError(RestfulError):
    """Error in response."""

    def __init__(self, response, content):
        RestfulError.__init__(self)
        self.response = response
        self.content = content


class UnexpectedResponseError(ResponseError):
    """An unexpected response was received."""

    def __str__(self):
        return '%s: %s' % (self.response.status, self.response.reason)


class HTTPError(ResponseError):
    """An HTTP non-2xx response code was received."""

    def __str__(self):
        """Show the error code, response headers, and response body."""
        headers = "\n".join(["%s: %s" % pair
                             for pair in sorted(self.response.items())])
        return ("HTTP Error %s: %s\n"
                "Response headers:\n---\n%s\n---\n"
                "Response body:\n---\n%s\n---\n") % (
            self.response.status, self.response.reason, headers, self.content)
