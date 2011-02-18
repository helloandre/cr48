# Copyright 2009 Canonical Ltd.

# This file is part of lazr.restfulclient.
#
# lazr.restfulclient is free software: you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation, version 3 of the
# License.
#
# lazr.restfulclient is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with lazr.restfulclient. If not, see <http://www.gnu.org/licenses/>.

"""Tests for the Credentials class."""

__metaclass__ = type


import os
import os.path
import shutil
import tempfile
import unittest

from lazr.restfulclient.authorize.oauth import AccessToken, OAuthAuthorizer


class TestCredentialsSaveAndLoad(unittest.TestCase):
    """Test for saving and loading credentials into an Authorizer."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_save_to_and_load_from__path(self):
        # Credentials can be saved to and loaded from a file using
        # save_to_path() and load_from_path().
        credentials_path = os.path.join(self.temp_dir, 'credentials')
        credentials = OAuthAuthorizer(
            'consumer.key', consumer_secret='consumer.secret',
            access_token=AccessToken('access.key', 'access.secret'))
        credentials.save_to_path(credentials_path)
        self.assertTrue(os.path.exists(credentials_path))

        loaded_credentials = OAuthAuthorizer.load_from_path(credentials_path)
        self.assertEqual(loaded_credentials.consumer.key, 'consumer.key')
        self.assertEqual(
            loaded_credentials.consumer.secret, 'consumer.secret')
        self.assertEqual(
            loaded_credentials.access_token.key, 'access.key')
        self.assertEqual(
            loaded_credentials.access_token.secret, 'access.secret')

def test_suite():
    return unittest.TestLoader().loadTestsFromName(__name__)
