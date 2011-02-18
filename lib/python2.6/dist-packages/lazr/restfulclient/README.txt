..
    This file is part of lazr.restfulclient.

    lazr.restfulclient is free software: you can redistribute it and/or modify it
    under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, version 3 of the License.

    lazr.restfulclient is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
    License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with lazr.restfulclient.  If not, see <http://www.gnu.org/licenses/>.

LAZR restfulclient
************

This is a pure template for new lazr namespace packages.

Please see https://dev.launchpad.net/LazrStyleGuide and
https://dev.launchpad.net/Hacking for how to develop in this
package.

This is an example Sphinx_ `Table of contents`_.  If you add files to the docs
directory, you should probably improve it.

.. toctree::
   :glob:

   *
   docs/*

.. _Sphinx: http://sphinx.pocoo.org/
.. _Table of contents: http://sphinx.pocoo.org/concepts.html#the-toc-tree

Importable
==========

The lazr.restfulclient package is importable, and has a version number.

    >>> import lazr.restfulclient
    >>> print 'VERSION:', lazr.restfulclient.__version__
    VERSION: ...
