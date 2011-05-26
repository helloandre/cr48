# We can test part of the module without zlib.
try:
    import zlib
except ImportError:
    zlib = None

import zipfile, os, unittest, sys, shutil, struct

from StringIO import StringIO
from tempfile import TemporaryFile
from random import randint, random

import test.test_support as support
from test.test_support import TESTFN, run_unittest, findfile

TESTFN2 = TESTFN + "2"
TESTFNDIR = TESTFN + "d"
FIXEDTEST_SIZE = 1000

SMALL_TEST_DATA = [('_ziptest1', '1q2w3e4r5t'),
                   ('ziptest2dir/_ziptest2', 'qawsedrftg'),
                   ('/ziptest2dir/ziptest3dir/_ziptest3', 'azsxdcfvgb'),
                   ('ziptest2dir/ziptest3dir/ziptest4dir/_ziptest3', '6y7u8i9o0p')]

class TestsWithSourceFile(unittest.TestCase):
    def setUp(self):
        self.line_gen = ["Zipfile test line %d. random float: %f" % (i, random())
                          for i in xrange(FIXEDTEST_SIZE)]
        self.data = '\n'.join(self.line_gen) + '\n'

        # Make a source file with some lines
        fp = open(TESTFN, "wb")
        fp.write(self.data)
        fp.close()

    def makeTestArchive(self, f, compression):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(f, "w", compression)
        zipfp.write(TESTFN, "another"+os.extsep+"name")
        zipfp.write(TESTFN, TESTFN)
        zipfp.writestr("strfile", self.data)
        zipfp.close()

    def zipTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        self.assertEqual(zipfp.read(TESTFN), self.data)
        self.assertEqual(zipfp.read("another"+os.extsep+"name"), self.data)
        self.assertEqual(zipfp.read("strfile"), self.data)

        # Print the ZIP directory
        fp = StringIO()
        stdout = sys.stdout
        try:
            sys.stdout = fp

            zipfp.printdir()
        finally:
            sys.stdout = stdout

        directory = fp.getvalue()
        lines = directory.splitlines()
        self.assertEquals(len(lines), 4) # Number of files + header

        self.assert_('File Name' in lines[0])
        self.assert_('Modified' in lines[0])
        self.assert_('Size' in lines[0])

        fn, date, time, size = lines[1].split()
        self.assertEquals(fn, 'another.name')
        # XXX: timestamp is not tested
        self.assertEquals(size, str(len(self.data)))

        # Check the namelist
        names = zipfp.namelist()
        self.assertEquals(len(names), 3)
        self.assert_(TESTFN in names)
        self.assert_("another"+os.extsep+"name" in names)
        self.assert_("strfile" in names)

        # Check infolist
        infos = zipfp.infolist()
        names = [ i.filename for i in infos ]
        self.assertEquals(len(names), 3)
        self.assert_(TESTFN in names)
        self.assert_("another"+os.extsep+"name" in names)
        self.assert_("strfile" in names)
        for i in infos:
            self.assertEquals(i.file_size, len(self.data))

        # check getinfo
        for nm in (TESTFN, "another"+os.extsep+"name", "strfile"):
            info = zipfp.getinfo(nm)
            self.assertEquals(info.filename, nm)
            self.assertEquals(info.file_size, len(self.data))

        # Check that testzip doesn't raise an exception
        zipfp.testzip()
        zipfp.close()

    def testStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipTest(f, zipfile.ZIP_STORED)

    def zipOpenTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        zipdata1 = []
        zipopen1 = zipfp.open(TESTFN)
        while 1:
            read_data = zipopen1.read(256)
            if not read_data:
                break
            zipdata1.append(read_data)

        zipdata2 = []
        zipopen2 = zipfp.open("another"+os.extsep+"name")
        while 1:
            read_data = zipopen2.read(256)
            if not read_data:
                break
            zipdata2.append(read_data)

        self.assertEqual(''.join(zipdata1), self.data)
        self.assertEqual(''.join(zipdata2), self.data)
        zipfp.close()

    def testOpenStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipOpenTest(f, zipfile.ZIP_STORED)

    def testOpenViaZipInfo(self):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED)
        zipfp.writestr("name", "foo")
        zipfp.writestr("name", "bar")
        zipfp.close()

        zipfp = zipfile.ZipFile(TESTFN2, "r")
        infos = zipfp.infolist()
        data = ""
        for info in infos:
            data += zipfp.open(info).read()
        self.assert_(data == "foobar" or data == "barfoo")
        data = ""
        for info in infos:
            data += zipfp.read(info)
        self.assert_(data == "foobar" or data == "barfoo")
        zipfp.close()

    def zipRandomOpenTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        zipdata1 = []
        zipopen1 = zipfp.open(TESTFN)
        while 1:
            read_data = zipopen1.read(randint(1, 1024))
            if not read_data:
                break
            zipdata1.append(read_data)

        self.assertEqual(''.join(zipdata1), self.data)
        zipfp.close()

    def testRandomOpenStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipRandomOpenTest(f, zipfile.ZIP_STORED)

    def zipReadlineTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        zipopen = zipfp.open(TESTFN)
        for line in self.line_gen:
            linedata = zipopen.readline()
            self.assertEqual(linedata, line + '\n')

        zipfp.close()

    def zipReadlinesTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        ziplines = zipfp.open(TESTFN).readlines()
        for line, zipline in zip(self.line_gen, ziplines):
            self.assertEqual(zipline, line + '\n')

        zipfp.close()

    def zipIterlinesTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        for line, zipline in zip(self.line_gen, zipfp.open(TESTFN)):
            self.assertEqual(zipline, line + '\n')

        zipfp.close()

    def testReadlineStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipReadlineTest(f, zipfile.ZIP_STORED)

    def testReadlinesStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipReadlinesTest(f, zipfile.ZIP_STORED)

    def testIterlinesStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipIterlinesTest(f, zipfile.ZIP_STORED)

    if zlib:
        def testDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipTest(f, zipfile.ZIP_DEFLATED)

        def testOpenDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipOpenTest(f, zipfile.ZIP_DEFLATED)

        def testRandomOpenDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipRandomOpenTest(f, zipfile.ZIP_DEFLATED)

        def testReadlineDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipReadlineTest(f, zipfile.ZIP_DEFLATED)

        def testReadlinesDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipReadlinesTest(f, zipfile.ZIP_DEFLATED)

        def testIterlinesDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipIterlinesTest(f, zipfile.ZIP_DEFLATED)

        def testLowCompression(self):
            # Checks for cases where compressed data is larger than original
            # Create the ZIP archive
            zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_DEFLATED)
            zipfp.writestr("strfile", '12')
            zipfp.close()

            # Get an open object for strfile
            zipfp = zipfile.ZipFile(TESTFN2, "r", zipfile.ZIP_DEFLATED)
            openobj = zipfp.open("strfile")
            self.assertEqual(openobj.read(1), '1')
            self.assertEqual(openobj.read(1), '2')

    def testAbsoluteArcnames(self):
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED)
        zipfp.write(TESTFN, "/absolute")
        zipfp.close()

        zipfp = zipfile.ZipFile(TESTFN2, "r", zipfile.ZIP_STORED)
        self.assertEqual(zipfp.namelist(), ["absolute"])
        zipfp.close()

    def testAppendToZipFile(self):
        # Test appending to an existing zipfile
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED)
        zipfp.write(TESTFN, TESTFN)
        zipfp.close()
        zipfp = zipfile.ZipFile(TESTFN2, "a", zipfile.ZIP_STORED)
        zipfp.writestr("strfile", self.data)
        self.assertEqual(zipfp.namelist(), [TESTFN, "strfile"])
        zipfp.close()

    def testAppendToNonZipFile(self):
        # Test appending to an existing file that is not a zipfile
        # NOTE: this test fails if len(d) < 22 because of the first
        # line "fpin.seek(-22, 2)" in _EndRecData
        d = 'I am not a ZipFile!'*10
        f = file(TESTFN2, 'wb')
        f.write(d)
        f.close()
        zipfp = zipfile.ZipFile(TESTFN2, "a", zipfile.ZIP_STORED)
        zipfp.write(TESTFN, TESTFN)
        zipfp.close()

        f = file(TESTFN2, 'rb')
        f.seek(len(d))
        zipfp = zipfile.ZipFile(f, "r")
        self.assertEqual(zipfp.namelist(), [TESTFN])
        zipfp.close()
        f.close()

    def test_WriteDefaultName(self):
        # Check that calling ZipFile.write without arcname specified produces the expected result
        zipfp = zipfile.ZipFile(TESTFN2, "w")
        zipfp.write(TESTFN)
        self.assertEqual(zipfp.read(TESTFN), file(TESTFN).read())
        zipfp.close()

    def test_PerFileCompression(self):
        # Check that files within a Zip archive can have different compression options
        zipfp = zipfile.ZipFile(TESTFN2, "w")
        zipfp.write(TESTFN, 'storeme', zipfile.ZIP_STORED)
        zipfp.write(TESTFN, 'deflateme', zipfile.ZIP_DEFLATED)
        sinfo = zipfp.getinfo('storeme')
        dinfo = zipfp.getinfo('deflateme')
        self.assertEqual(sinfo.compress_type, zipfile.ZIP_STORED)
        self.assertEqual(dinfo.compress_type, zipfile.ZIP_DEFLATED)
        zipfp.close()

    def test_WriteToReadonly(self):
        # Check that trying to call write() on a readonly ZipFile object
        # raises a RuntimeError
        zipf = zipfile.ZipFile(TESTFN2, mode="w")
        zipf.writestr("somefile.txt", "bogus")
        zipf.close()
        zipf = zipfile.ZipFile(TESTFN2, mode="r")
        self.assertRaises(RuntimeError, zipf.write, TESTFN)
        zipf.close()

    def testExtract(self):
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED)
        for fpath, fdata in SMALL_TEST_DATA:
            zipfp.writestr(fpath, fdata)
        zipfp.close()

        zipfp = zipfile.ZipFile(TESTFN2, "r")
        for fpath, fdata in SMALL_TEST_DATA:
            writtenfile = zipfp.extract(fpath)

            # make sure it was written to the right place
            if os.path.isabs(fpath):
                correctfile = os.path.join(os.getcwd(), fpath[1:])
            else:
                correctfile = os.path.join(os.getcwd(), fpath)
            correctfile = os.path.normpath(correctfile)

            self.assertEqual(writtenfile, correctfile)

            # make sure correct data is in correct file
            self.assertEqual(fdata, file(writtenfile, "rb").read())

            os.remove(writtenfile)

        zipfp.close()

        # remove the test file subdirectories
        shutil.rmtree(os.path.join(os.getcwd(), 'ziptest2dir'))

    def testExtractAll(self):
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED)
        for fpath, fdata in SMALL_TEST_DATA:
            zipfp.writestr(fpath, fdata)
        zipfp.close()

        zipfp = zipfile.ZipFile(TESTFN2, "r")
        zipfp.extractall()
        for fpath, fdata in SMALL_TEST_DATA:
            if os.path.isabs(fpath):
                outfile = os.path.join(os.getcwd(), fpath[1:])
            else:
                outfile = os.path.join(os.getcwd(), fpath)

            self.assertEqual(fdata, file(outfile, "rb").read())

            os.remove(outfile)

        zipfp.close()

        # remove the test file subdirectories
        shutil.rmtree(os.path.join(os.getcwd(), 'ziptest2dir'))

    def zip_test_writestr_permissions(self, f, compression):
        # Make sure that writestr creates files with mode 0600,
        # when it is passed a name rather than a ZipInfo instance.

        self.makeTestArchive(f, compression)
        zipfp = zipfile.ZipFile(f, "r")
        zinfo = zipfp.getinfo('strfile')
        self.assertEqual(zinfo.external_attr, 0600 << 16)

    def test_writestr_permissions(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zip_test_writestr_permissions(f, zipfile.ZIP_STORED)

    def tearDown(self):
        os.remove(TESTFN)
        os.remove(TESTFN2)

class TestZip64InSmallFiles(unittest.TestCase):
    # These tests test the ZIP64 functionality without using large files,
    # see test_zipfile64 for proper tests.

    def setUp(self):
        self._limit = zipfile.ZIP64_LIMIT
        zipfile.ZIP64_LIMIT = 5

        line_gen = ("Test of zipfile line %d." % i for i in range(0, FIXEDTEST_SIZE))
        self.data = '\n'.join(line_gen)

        # Make a source file with some lines
        fp = open(TESTFN, "wb")
        fp.write(self.data)
        fp.close()

    def largeFileExceptionTest(self, f, compression):
        zipfp = zipfile.ZipFile(f, "w", compression)
        self.assertRaises(zipfile.LargeZipFile,
                zipfp.write, TESTFN, "another"+os.extsep+"name")
        zipfp.close()

    def largeFileExceptionTest2(self, f, compression):
        zipfp = zipfile.ZipFile(f, "w", compression)
        self.assertRaises(zipfile.LargeZipFile,
                zipfp.writestr, "another"+os.extsep+"name", self.data)
        zipfp.close()

    def testLargeFileException(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.largeFileExceptionTest(f, zipfile.ZIP_STORED)
            self.largeFileExceptionTest2(f, zipfile.ZIP_STORED)

    def zipTest(self, f, compression):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(f, "w", compression, allowZip64=True)
        zipfp.write(TESTFN, "another"+os.extsep+"name")
        zipfp.write(TESTFN, TESTFN)
        zipfp.writestr("strfile", self.data)
        zipfp.close()

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        self.assertEqual(zipfp.read(TESTFN), self.data)
        self.assertEqual(zipfp.read("another"+os.extsep+"name"), self.data)
        self.assertEqual(zipfp.read("strfile"), self.data)

        # Print the ZIP directory
        fp = StringIO()
        stdout = sys.stdout
        try:
            sys.stdout = fp

            zipfp.printdir()
        finally:
            sys.stdout = stdout

        directory = fp.getvalue()
        lines = directory.splitlines()
        self.assertEquals(len(lines), 4) # Number of files + header

        self.assert_('File Name' in lines[0])
        self.assert_('Modified' in lines[0])
        self.assert_('Size' in lines[0])

        fn, date, time, size = lines[1].split()
        self.assertEquals(fn, 'another.name')
        # XXX: timestamp is not tested
        self.assertEquals(size, str(len(self.data)))

        # Check the namelist
        names = zipfp.namelist()
        self.assertEquals(len(names), 3)
        self.assert_(TESTFN in names)
        self.assert_("another"+os.extsep+"name" in names)
        self.assert_("strfile" in names)

        # Check infolist
        infos = zipfp.infolist()
        names = [ i.filename for i in infos ]
        self.assertEquals(len(names), 3)
        self.assert_(TESTFN in names)
        self.assert_("another"+os.extsep+"name" in names)
        self.assert_("strfile" in names)
        for i in infos:
            self.assertEquals(i.file_size, len(self.data))

        # check getinfo
        for nm in (TESTFN, "another"+os.extsep+"name", "strfile"):
            info = zipfp.getinfo(nm)
            self.assertEquals(info.filename, nm)
            self.assertEquals(info.file_size, len(self.data))

        # Check that testzip doesn't raise an exception
        zipfp.testzip()


        zipfp.close()

    def testStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipTest(f, zipfile.ZIP_STORED)


    if zlib:
        def testDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.zipTest(f, zipfile.ZIP_DEFLATED)

    def testAbsoluteArcnames(self):
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_STORED, allowZip64=True)
        zipfp.write(TESTFN, "/absolute")
        zipfp.close()

        zipfp = zipfile.ZipFile(TESTFN2, "r", zipfile.ZIP_STORED)
        self.assertEqual(zipfp.namelist(), ["absolute"])
        zipfp.close()

    def tearDown(self):
        zipfile.ZIP64_LIMIT = self._limit
        os.remove(TESTFN)
        os.remove(TESTFN2)

class PyZipFileTests(unittest.TestCase):
    def testWritePyfile(self):
        zipfp  = zipfile.PyZipFile(TemporaryFile(), "w")
        fn = __file__
        if fn.endswith('.pyc') or fn.endswith('.pyo'):
            fn = fn[:-1]

        zipfp.writepy(fn)

        bn = os.path.basename(fn)
        self.assert_(bn not in zipfp.namelist())
        self.assert_(bn + 'o' in zipfp.namelist() or bn + 'c' in zipfp.namelist())
        zipfp.close()


        zipfp  = zipfile.PyZipFile(TemporaryFile(), "w")
        fn = __file__
        if fn.endswith('.pyc') or fn.endswith('.pyo'):
            fn = fn[:-1]

        zipfp.writepy(fn, "testpackage")

        bn = "%s/%s"%("testpackage", os.path.basename(fn))
        self.assert_(bn not in zipfp.namelist())
        self.assert_(bn + 'o' in zipfp.namelist() or bn + 'c' in zipfp.namelist())
        zipfp.close()

    def testWritePythonPackage(self):
        import email
        packagedir = os.path.dirname(email.__file__)

        zipfp  = zipfile.PyZipFile(TemporaryFile(), "w")
        zipfp.writepy(packagedir)

        # Check for a couple of modules at different levels of the hieararchy
        names = zipfp.namelist()
        self.assert_('email/__init__.pyo' in names or 'email/__init__.pyc' in names)
        self.assert_('email/mime/text.pyo' in names or 'email/mime/text.pyc' in names)

    def testWritePythonDirectory(self):
        os.mkdir(TESTFN2)
        try:
            fp = open(os.path.join(TESTFN2, "mod1.py"), "w")
            fp.write("print 42\n")
            fp.close()

            fp = open(os.path.join(TESTFN2, "mod2.py"), "w")
            fp.write("print 42 * 42\n")
            fp.close()

            fp = open(os.path.join(TESTFN2, "mod2.txt"), "w")
            fp.write("bla bla bla\n")
            fp.close()

            zipfp  = zipfile.PyZipFile(TemporaryFile(), "w")
            zipfp.writepy(TESTFN2)

            names = zipfp.namelist()
            self.assert_('mod1.pyc' in names or 'mod1.pyo' in names)
            self.assert_('mod2.pyc' in names or 'mod2.pyo' in names)
            self.assert_('mod2.txt' not in names)

        finally:
            shutil.rmtree(TESTFN2)

    def testWriteNonPyfile(self):
        zipfp  = zipfile.PyZipFile(TemporaryFile(), "w")
        file(TESTFN, 'w').write('most definitely not a python file')
        self.assertRaises(RuntimeError, zipfp.writepy, TESTFN)
        os.remove(TESTFN)


class OtherTests(unittest.TestCase):
    def testUnicodeFilenames(self):
        zf = zipfile.ZipFile(TESTFN, "w")
        zf.writestr(u"foo.txt", "Test for unicode filename")
        zf.writestr(u"\xf6.txt", "Test for unicode filename")
        self.assertTrue(isinstance(zf.infolist()[0].filename, unicode))
        zf.close()
        zf = zipfile.ZipFile(TESTFN, "r")
        self.assertEqual(zf.filelist[0].filename, "foo.txt")
        self.assertEqual(zf.filelist[1].filename, u"\xf6.txt")
        zf.close()

    def testCreateNonExistentFileForAppend(self):
        if os.path.exists(TESTFN):
            os.unlink(TESTFN)

        filename = 'testfile.txt'
        content = 'hello, world. this is some content.'

        try:
            zf = zipfile.ZipFile(TESTFN, 'a')
            zf.writestr(filename, content)
            zf.close()
        except IOError, (errno, errmsg):
            self.fail('Could not append data to a non-existent zip file.')

        self.assert_(os.path.exists(TESTFN))

        zf = zipfile.ZipFile(TESTFN, 'r')
        self.assertEqual(zf.read(filename), content)
        zf.close()

    def testCloseErroneousFile(self):
        # This test checks that the ZipFile constructor closes the file object
        # it opens if there's an error in the file.  If it doesn't, the traceback
        # holds a reference to the ZipFile object and, indirectly, the file object.
        # On Windows, this causes the os.unlink() call to fail because the
        # underlying file is still open.  This is SF bug #412214.
        #
        fp = open(TESTFN, "w")
        fp.write("this is not a legal zip file\n")
        fp.close()
        try:
            zf = zipfile.ZipFile(TESTFN)
        except zipfile.BadZipfile:
            pass

    def testIsZipErroneousFile(self):
        # This test checks that the is_zipfile function correctly identifies
        # a file that is not a zip file
        fp = open(TESTFN, "w")
        fp.write("this is not a legal zip file\n")
        fp.close()
        chk = zipfile.is_zipfile(TESTFN)
        self.assert_(chk is False)

    def testIsZipValidFile(self):
        # This test checks that the is_zipfile function correctly identifies
        # a file that is a zip file
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        chk = zipfile.is_zipfile(TESTFN)
        self.assert_(chk is True)

    def testNonExistentFileRaisesIOError(self):
        # make sure we don't raise an AttributeError when a partially-constructed
        # ZipFile instance is finalized; this tests for regression on SF tracker
        # bug #403871.

        # The bug we're testing for caused an AttributeError to be raised
        # when a ZipFile instance was created for a file that did not
        # exist; the .fp member was not initialized but was needed by the
        # __del__() method.  Since the AttributeError is in the __del__(),
        # it is ignored, but the user should be sufficiently annoyed by
        # the message on the output that regression will be noticed
        # quickly.
        self.assertRaises(IOError, zipfile.ZipFile, TESTFN)

    def test_empty_file_raises_BadZipFile(self):
        f = open(TESTFN, 'w')
        f.close()
        self.assertRaises(zipfile.BadZipfile, zipfile.ZipFile, TESTFN)

        f = open(TESTFN, 'w')
        f.write("short file")
        f.close()
        self.assertRaises(zipfile.BadZipfile, zipfile.ZipFile, TESTFN)

    def testClosedZipRaisesRuntimeError(self):
        # Verify that testzip() doesn't swallow inappropriate exceptions.
        data = StringIO()
        zipf = zipfile.ZipFile(data, mode="w")
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()

        # This is correct; calling .read on a closed ZipFile should throw
        # a RuntimeError, and so should calling .testzip.  An earlier
        # version of .testzip would swallow this exception (and any other)
        # and report that the first file in the archive was corrupt.
        self.assertRaises(RuntimeError, zipf.read, "foo.txt")
        self.assertRaises(RuntimeError, zipf.open, "foo.txt")
        self.assertRaises(RuntimeError, zipf.testzip)
        self.assertRaises(RuntimeError, zipf.writestr, "bogus.txt", "bogus")
        file(TESTFN, 'w').write('zipfile test data')
        self.assertRaises(RuntimeError, zipf.write, TESTFN)

    def test_BadConstructorMode(self):
        # Check that bad modes passed to ZipFile constructor are caught
        self.assertRaises(RuntimeError, zipfile.ZipFile, TESTFN, "q")

    def test_BadOpenMode(self):
        # Check that bad modes passed to ZipFile.open are caught
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        zipf = zipfile.ZipFile(TESTFN, mode="r")
        # read the data to make sure the file is there
        zipf.read("foo.txt")
        self.assertRaises(RuntimeError, zipf.open, "foo.txt", "q")
        zipf.close()

    def test_Read0(self):
        # Check that calling read(0) on a ZipExtFile object returns an empty
        # string and doesn't advance file pointer
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        # read the data to make sure the file is there
        f = zipf.open("foo.txt")
        for i in xrange(FIXEDTEST_SIZE):
            self.assertEqual(f.read(0), '')

        self.assertEqual(f.read(), "O, for a Muse of Fire!")
        zipf.close()

    def test_OpenNonexistentItem(self):
        # Check that attempting to call open() for an item that doesn't
        # exist in the archive raises a RuntimeError
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        self.assertRaises(KeyError, zipf.open, "foo.txt", "r")

    def test_BadCompressionMode(self):
        # Check that bad compression methods passed to ZipFile.open are caught
        self.assertRaises(RuntimeError, zipfile.ZipFile, TESTFN, "w", -1)

    def test_NullByteInFilename(self):
        # Check that a filename containing a null byte is properly terminated
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.writestr("foo.txt\x00qqq", "O, for a Muse of Fire!")
        self.assertEqual(zipf.namelist(), ['foo.txt'])

    def test_StructSizes(self):
        # check that ZIP internal structure sizes are calculated correctly
        self.assertEqual(zipfile.sizeEndCentDir, 22)
        self.assertEqual(zipfile.sizeCentralDir, 46)
        self.assertEqual(zipfile.sizeEndCentDir64, 56)
        self.assertEqual(zipfile.sizeEndCentDir64Locator, 20)

    def testComments(self):
        # This test checks that comments on the archive are handled properly

        # check default comment is empty
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        self.assertEqual(zipf.comment, '')
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        zipfr = zipfile.ZipFile(TESTFN, mode="r")
        self.assertEqual(zipfr.comment, '')
        zipfr.close()

        # check a simple short comment
        comment = 'Bravely taking to his feet, he beat a very brave retreat.'
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.comment = comment
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        zipfr = zipfile.ZipFile(TESTFN, mode="r")
        self.assertEqual(zipfr.comment, comment)
        zipfr.close()

        # check a comment of max length
        comment2 = ''.join(['%d' % (i**3 % 10) for i in xrange((1 << 16)-1)])
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.comment = comment2
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        zipfr = zipfile.ZipFile(TESTFN, mode="r")
        self.assertEqual(zipfr.comment, comment2)
        zipfr.close()

        # check a comment that is too long is truncated
        zipf = zipfile.ZipFile(TESTFN, mode="w")
        zipf.comment = comment2 + 'oops'
        zipf.writestr("foo.txt", "O, for a Muse of Fire!")
        zipf.close()
        zipfr = zipfile.ZipFile(TESTFN, mode="r")
        self.assertEqual(zipfr.comment, comment2)
        zipfr.close()

    def tearDown(self):
        support.unlink(TESTFN)
        support.unlink(TESTFN2)

class DecryptionTests(unittest.TestCase):
    # This test checks that ZIP decryption works. Since the library does not
    # support encryption at the moment, we use a pre-generated encrypted
    # ZIP file

    data = (
    'PK\x03\x04\x14\x00\x01\x00\x00\x00n\x92i.#y\xef?&\x00\x00\x00\x1a\x00'
    '\x00\x00\x08\x00\x00\x00test.txt\xfa\x10\xa0gly|\xfa-\xc5\xc0=\xf9y'
    '\x18\xe0\xa8r\xb3Z}Lg\xbc\xae\xf9|\x9b\x19\xe4\x8b\xba\xbb)\x8c\xb0\xdbl'
    'PK\x01\x02\x14\x00\x14\x00\x01\x00\x00\x00n\x92i.#y\xef?&\x00\x00\x00'
    '\x1a\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x01\x00 \x00\xb6\x81'
    '\x00\x00\x00\x00test.txtPK\x05\x06\x00\x00\x00\x00\x01\x00\x01\x006\x00'
    '\x00\x00L\x00\x00\x00\x00\x00' )
    data2 = (
    'PK\x03\x04\x14\x00\t\x00\x08\x00\xcf}38xu\xaa\xb2\x14\x00\x00\x00\x00\x02'
    '\x00\x00\x04\x00\x15\x00zeroUT\t\x00\x03\xd6\x8b\x92G\xda\x8b\x92GUx\x04'
    '\x00\xe8\x03\xe8\x03\xc7<M\xb5a\xceX\xa3Y&\x8b{oE\xd7\x9d\x8c\x98\x02\xc0'
    'PK\x07\x08xu\xaa\xb2\x14\x00\x00\x00\x00\x02\x00\x00PK\x01\x02\x17\x03'
    '\x14\x00\t\x00\x08\x00\xcf}38xu\xaa\xb2\x14\x00\x00\x00\x00\x02\x00\x00'
    '\x04\x00\r\x00\x00\x00\x00\x00\x00\x00\x00\x00\xa4\x81\x00\x00\x00\x00ze'
    'roUT\x05\x00\x03\xd6\x8b\x92GUx\x00\x00PK\x05\x06\x00\x00\x00\x00\x01'
    '\x00\x01\x00?\x00\x00\x00[\x00\x00\x00\x00\x00' )

    plain = 'zipfile.py encryption test'
    plain2 = '\x00'*512

    def setUp(self):
        fp = open(TESTFN, "wb")
        fp.write(self.data)
        fp.close()
        self.zip = zipfile.ZipFile(TESTFN, "r")
        fp = open(TESTFN2, "wb")
        fp.write(self.data2)
        fp.close()
        self.zip2 = zipfile.ZipFile(TESTFN2, "r")

    def tearDown(self):
        self.zip.close()
        os.unlink(TESTFN)
        self.zip2.close()
        os.unlink(TESTFN2)

    def testNoPassword(self):
        # Reading the encrypted file without password
        # must generate a RunTime exception
        self.assertRaises(RuntimeError, self.zip.read, "test.txt")
        self.assertRaises(RuntimeError, self.zip2.read, "zero")

    def testBadPassword(self):
        self.zip.setpassword("perl")
        self.assertRaises(RuntimeError, self.zip.read, "test.txt")
        self.zip2.setpassword("perl")
        self.assertRaises(RuntimeError, self.zip2.read, "zero")

    def testGoodPassword(self):
        self.zip.setpassword("python")
        self.assertEquals(self.zip.read("test.txt"), self.plain)
        self.zip2.setpassword("12345")
        self.assertEquals(self.zip2.read("zero"), self.plain2)


class TestsWithRandomBinaryFiles(unittest.TestCase):
    def setUp(self):
        datacount = randint(16, 64)*1024 + randint(1, 1024)
        self.data = ''.join((struct.pack('<f', random()*randint(-1000, 1000)) for i in xrange(datacount)))

        # Make a source file with some lines
        fp = open(TESTFN, "wb")
        fp.write(self.data)
        fp.close()

    def tearDown(self):
        support.unlink(TESTFN)
        support.unlink(TESTFN2)

    def makeTestArchive(self, f, compression):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(f, "w", compression)
        zipfp.write(TESTFN, "another"+os.extsep+"name")
        zipfp.write(TESTFN, TESTFN)
        zipfp.close()

    def zipTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        testdata = zipfp.read(TESTFN)
        self.assertEqual(len(testdata), len(self.data))
        self.assertEqual(testdata, self.data)
        self.assertEqual(zipfp.read("another"+os.extsep+"name"), self.data)
        zipfp.close()

    def testStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipTest(f, zipfile.ZIP_STORED)

    def zipOpenTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        zipdata1 = []
        zipopen1 = zipfp.open(TESTFN)
        while 1:
            read_data = zipopen1.read(256)
            if not read_data:
                break
            zipdata1.append(read_data)

        zipdata2 = []
        zipopen2 = zipfp.open("another"+os.extsep+"name")
        while 1:
            read_data = zipopen2.read(256)
            if not read_data:
                break
            zipdata2.append(read_data)

        testdata1 = ''.join(zipdata1)
        self.assertEqual(len(testdata1), len(self.data))
        self.assertEqual(testdata1, self.data)

        testdata2 = ''.join(zipdata2)
        self.assertEqual(len(testdata1), len(self.data))
        self.assertEqual(testdata1, self.data)
        zipfp.close()

    def testOpenStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipOpenTest(f, zipfile.ZIP_STORED)

    def zipRandomOpenTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r", compression)
        zipdata1 = []
        zipopen1 = zipfp.open(TESTFN)
        while 1:
            read_data = zipopen1.read(randint(1, 1024))
            if not read_data:
                break
            zipdata1.append(read_data)

        testdata = ''.join(zipdata1)
        self.assertEqual(len(testdata), len(self.data))
        self.assertEqual(testdata, self.data)
        zipfp.close()

    def testRandomOpenStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.zipRandomOpenTest(f, zipfile.ZIP_STORED)

class TestsWithMultipleOpens(unittest.TestCase):
    def setUp(self):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(TESTFN2, "w", zipfile.ZIP_DEFLATED)
        zipfp.writestr('ones', '1'*FIXEDTEST_SIZE)
        zipfp.writestr('twos', '2'*FIXEDTEST_SIZE)
        zipfp.close()

    def testSameFile(self):
        # Verify that (when the ZipFile is in control of creating file objects)
        # multiple open() calls can be made without interfering with each other.
        zipf = zipfile.ZipFile(TESTFN2, mode="r")
        zopen1 = zipf.open('ones')
        zopen2 = zipf.open('ones')
        data1 = zopen1.read(500)
        data2 = zopen2.read(500)
        data1 += zopen1.read(500)
        data2 += zopen2.read(500)
        self.assertEqual(data1, data2)
        zipf.close()

    def testDifferentFile(self):
        # Verify that (when the ZipFile is in control of creating file objects)
        # multiple open() calls can be made without interfering with each other.
        zipf = zipfile.ZipFile(TESTFN2, mode="r")
        zopen1 = zipf.open('ones')
        zopen2 = zipf.open('twos')
        data1 = zopen1.read(500)
        data2 = zopen2.read(500)
        data1 += zopen1.read(500)
        data2 += zopen2.read(500)
        self.assertEqual(data1, '1'*FIXEDTEST_SIZE)
        self.assertEqual(data2, '2'*FIXEDTEST_SIZE)
        zipf.close()

    def testInterleaved(self):
        # Verify that (when the ZipFile is in control of creating file objects)
        # multiple open() calls can be made without interfering with each other.
        zipf = zipfile.ZipFile(TESTFN2, mode="r")
        zopen1 = zipf.open('ones')
        data1 = zopen1.read(500)
        zopen2 = zipf.open('twos')
        data2 = zopen2.read(500)
        data1 += zopen1.read(500)
        data2 += zopen2.read(500)
        self.assertEqual(data1, '1'*FIXEDTEST_SIZE)
        self.assertEqual(data2, '2'*FIXEDTEST_SIZE)
        zipf.close()

    def tearDown(self):
        os.remove(TESTFN2)

class TestWithDirectory(unittest.TestCase):
    def setUp(self):
        os.mkdir(TESTFN2)

    def testExtractDir(self):
        zipf = zipfile.ZipFile(findfile("zipdir.zip"))
        zipf.extractall(TESTFN2)
        self.assertTrue(os.path.isdir(os.path.join(TESTFN2, "a")))
        self.assertTrue(os.path.isdir(os.path.join(TESTFN2, "a", "b")))
        self.assertTrue(os.path.exists(os.path.join(TESTFN2, "a", "b", "c")))

    def test_bug_6050(self):
        # Extraction should succeed if directories already exist
        os.mkdir(os.path.join(TESTFN2, "a"))
        self.testExtractDir()

    def testStoreDir(self):
        os.mkdir(os.path.join(TESTFN2, "x"))
        zipf = zipfile.ZipFile(TESTFN, "w")
        zipf.write(os.path.join(TESTFN2, "x"), "x")
        self.assertTrue(zipf.filelist[0].filename.endswith("x/"))

    def tearDown(self):
        shutil.rmtree(TESTFN2)
        if os.path.exists(TESTFN):
            os.remove(TESTFN)


class UniversalNewlineTests(unittest.TestCase):
    def setUp(self):
        self.line_gen = ["Test of zipfile line %d." % i for i in xrange(FIXEDTEST_SIZE)]
        self.seps = ('\r', '\r\n', '\n')
        self.arcdata, self.arcfiles = {}, {}
        for n, s in enumerate(self.seps):
            self.arcdata[s] = s.join(self.line_gen) + s
            self.arcfiles[s] = '%s-%d' % (TESTFN, n)
            open(self.arcfiles[s], "wb").write(self.arcdata[s])

    def makeTestArchive(self, f, compression):
        # Create the ZIP archive
        zipfp = zipfile.ZipFile(f, "w", compression)
        for fn in self.arcfiles.values():
            zipfp.write(fn, fn)
        zipfp.close()

    def readTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        for sep, fn in self.arcfiles.items():
            zipdata = zipfp.open(fn, "rU").read()
            self.assertEqual(self.arcdata[sep], zipdata)

        zipfp.close()

    def readlineTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        for sep, fn in self.arcfiles.items():
            zipopen = zipfp.open(fn, "rU")
            for line in self.line_gen:
                linedata = zipopen.readline()
                self.assertEqual(linedata, line + '\n')

        zipfp.close()

    def readlinesTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        for sep, fn in self.arcfiles.items():
            ziplines = zipfp.open(fn, "rU").readlines()
            for line, zipline in zip(self.line_gen, ziplines):
                self.assertEqual(zipline, line + '\n')

        zipfp.close()

    def iterlinesTest(self, f, compression):
        self.makeTestArchive(f, compression)

        # Read the ZIP archive
        zipfp = zipfile.ZipFile(f, "r")
        for sep, fn in self.arcfiles.items():
            for line, zipline in zip(self.line_gen, zipfp.open(fn, "rU")):
                self.assertEqual(zipline, line + '\n')

        zipfp.close()

    def testReadStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.readTest(f, zipfile.ZIP_STORED)

    def testReadlineStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.readlineTest(f, zipfile.ZIP_STORED)

    def testReadlinesStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.readlinesTest(f, zipfile.ZIP_STORED)

    def testIterlinesStored(self):
        for f in (TESTFN2, TemporaryFile(), StringIO()):
            self.iterlinesTest(f, zipfile.ZIP_STORED)

    if zlib:
        def testReadDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.readTest(f, zipfile.ZIP_DEFLATED)

        def testReadlineDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.readlineTest(f, zipfile.ZIP_DEFLATED)

        def testReadlinesDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.readlinesTest(f, zipfile.ZIP_DEFLATED)

        def testIterlinesDeflated(self):
            for f in (TESTFN2, TemporaryFile(), StringIO()):
                self.iterlinesTest(f, zipfile.ZIP_DEFLATED)

    def tearDown(self):
        for sep, fn in self.arcfiles.items():
            os.remove(fn)
        support.unlink(TESTFN)
        support.unlink(TESTFN2)


def test_main():
    run_unittest(TestsWithSourceFile, TestZip64InSmallFiles, OtherTests,
                 PyZipFileTests, DecryptionTests, TestsWithMultipleOpens,
                 TestWithDirectory,
                 UniversalNewlineTests, TestsWithRandomBinaryFiles)

if __name__ == "__main__":
    test_main()
