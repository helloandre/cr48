# Copyright 2009 Canonical Ltd.

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

"""OAuth classes for use with lazr.restfulclient."""


from ConfigParser import SafeConfigParser
# Work around relative import behavior.  The below is equivalent to
# from oauth import oauth
oauth = __import__('oauth.oauth', {}).oauth
(OAuthConsumer, OAuthRequest, OAuthSignatureMethod_PLAINTEXT,
 OAuthToken) = (oauth.OAuthConsumer, oauth.OAuthRequest,
                oauth.OAuthSignatureMethod_PLAINTEXT, oauth.OAuthToken)

from lazr.restfulclient.authorize import HttpAuthorizer
from lazr.restfulclient.errors import CredentialsFileError

__metaclass__ = type
__all__ = [
    'AccessToken',
    'Consumer',
    'OAuthAuthorizer',
    ]


CREDENTIALS_FILE_VERSION = '1'


# These two classes are provided for convenience (so applications don't need
# to import from oauth.oauth), and to provide a default argument
# for secret.
class Consumer(oauth.OAuthConsumer):
    """An OAuth consumer (application)."""

    def __init__(self, key, secret=''):
        OAuthConsumer.__init__(self, key, secret)


class AccessToken(oauth.OAuthToken):
    """An OAuth access token."""

    def __init__(self, key, secret='', context=None):
        OAuthToken.__init__(self, key, secret)
        self.context = context


class OAuthAuthorizer(HttpAuthorizer):
    """A client that signs every outgoing request with OAuth credentials."""

    def __init__(self, consumer_name=None, consumer_secret='',
                 access_token=None, oauth_realm="OAuth"):
        self.consumer = None
        if consumer_name is not None:
            self.consumer = Consumer(consumer_name, consumer_secret)
        self.access_token = access_token
        self.oauth_realm = oauth_realm

    @property
    def user_agent_params(self):
        """Any information necessary to identify this user agent.

        In this case, the OAuth consumer name.
        """
        if self.consumer is None:
            return {}
        return {'oauth_consumer' : self.consumer.key}

    def load(self, readable_file):
        """Load credentials from a file-like object.

        This overrides the consumer and access token given in the constructor
        and replaces them with the values read from the file.

        :param readable_file: A file-like object to read the credentials from
        :type readable_file: Any object supporting the file-like `read()`
            method
        """
        # Attempt to load the access token from the file.
        parser = SafeConfigParser()
        parser.readfp(readable_file)
        # Check the version number and extract the access token and
        # secret.  Then convert these to the appropriate instances.
        if not parser.has_section(CREDENTIALS_FILE_VERSION):
            raise CredentialsFileError('No configuration for version %s' %
                                       CREDENTIALS_FILE_VERSION)
        consumer_key = parser.get(
            CREDENTIALS_FILE_VERSION, 'consumer_key')
        consumer_secret = parser.get(
            CREDENTIALS_FILE_VERSION, 'consumer_secret')
        self.consumer = Consumer(consumer_key, consumer_secret)
        access_token = parser.get(
            CREDENTIALS_FILE_VERSION, 'access_token')
        access_secret = parser.get(
            CREDENTIALS_FILE_VERSION, 'access_secret')
        self.access_token = AccessToken(access_token, access_secret)

    @classmethod
    def load_from_path(cls, path):
        """Convenience method for loading credentials from a file.

        Open the file, create the Credentials and load from the file,
        and finally close the file and return the newly created
        Credentials instance.

        :param path: In which file the credential file should be saved.
        :type path: string
        :return: The loaded Credentials instance.
        :rtype: `Credentials`
        """
        credentials = cls()
        credentials_file = open(path, 'r')
        credentials.load(credentials_file)
        credentials_file.close()
        return credentials

    def save(self, writable_file):
        """Write the credentials to the file-like object.

        :param writable_file: A file-like object to write the credentials to
        :type writable_file: Any object supporting the file-like `write()`
            method
        :raise CredentialsFileError: when there is either no consumer or no
            access token
        """
        if self.consumer is None:
            raise CredentialsFileError('No consumer')
        if self.access_token is None:
            raise CredentialsFileError('No access token')

        parser = SafeConfigParser()
        parser.add_section(CREDENTIALS_FILE_VERSION)
        parser.set(CREDENTIALS_FILE_VERSION,
                   'consumer_key', self.consumer.key)
        parser.set(CREDENTIALS_FILE_VERSION,
                   'consumer_secret', self.consumer.secret)
        parser.set(CREDENTIALS_FILE_VERSION,
                   'access_token', self.access_token.key)
        parser.set(CREDENTIALS_FILE_VERSION,
                   'access_secret', self.access_token.secret)
        parser.write(writable_file)

    def save_to_path(self, path):
        """Convenience method for saving credentials to a file.

        Create the file, call self.save(), and close the file. Existing
        files are overwritten.

        :param path: In which file the credential file should be saved.
        :type path: string
        """
        credentials_file = open(path, 'w')
        self.save(credentials_file)
        credentials_file.close()

    def authorizeRequest(self, absolute_uri, method, body, headers):
        """Sign a request with OAuth credentials."""
        oauth_request = OAuthRequest.from_consumer_and_token(
            self.consumer, self.access_token, http_url=absolute_uri)
        oauth_request.sign_request(
            OAuthSignatureMethod_PLAINTEXT(),
            self.consumer, self.access_token)
        headers.update(oauth_request.to_header(self.oauth_realm))
