// Written in the D programming language.
// This is a copy of phobos/std/file.d, with a rewrite of the file reader.

/**
Utilities for manipulating files and scanning directories. Functions
in this module handle files as a unit, e.g., read or write one _file
at a time. For opening files and manipulating them via handles refer
to module $(LINK2 std_stdio.html,$(D std.stdio)).

Macros:

Copyright: Copyright Digital Mars 2007 - 2011.
License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   $(WEB digitalmars.com, Walter Bright),
           $(WEB erdani.org, Andrei Alexandrescu),
           Jonathan M Davis
 */
module file;

import std.file;
import core.memory;
import core.stdc.stdio, core.stdc.stdlib, core.stdc.string,
       core.stdc.errno, std.algorithm, std.array, std.conv,
       std.datetime, std.exception, std.format, std.path, std.process,
       std.range, std.stdio, std.string, std.traits,
       std.typecons, std.typetuple, std.utf;


version (Windows)
{
    import core.sys.windows.windows, std.windows.syserror;
}
else version (Posix)
{
    import core.sys.posix.dirent, core.sys.posix.fcntl, core.sys.posix.sys.stat,
        core.sys.posix.sys.time, core.sys.posix.unistd, core.sys.posix.utime;
}
else
    static assert(false, "Module " ~ .stringof ~ " not implemented for this OS.");



private T cenforce(T)(T condition, lazy const(char)[] name, string file = __FILE__, size_t line = __LINE__)
{
    if (!condition)
    {
      version (Windows)
      {
        throw new FileException(name, .GetLastError(), file, line);
      }
      else version (Posix)
      {
        throw new FileException(name, .errno, file, line);
      }
    }
    return condition;
}

/* **********************************
 * Basic File operations.
 */

/********************************************
Read entire contents of file $(D name) and returns it as an untyped
array. If the file size is larger than $(D upTo), only $(D upTo)
bytes are read.

Example:

----
import std.file, std.stdio;
void main()
{
   auto bytes = cast(ubyte[]) read("filename", 5);
   if (bytes.length == 5)
       writefln("The fifth byte of the file is 0x%x", bytes[4]);
}
----

Returns: Untyped array of bytes _read.

Throws: $(D FileException) on error.
 */
void[] myRead(in char[] name, size_t upTo = size_t.max)
{
    version(Windows)
    {
        alias TypeTuple!(GENERIC_READ,
                FILE_SHARE_READ, (SECURITY_ATTRIBUTES*).init, OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
                HANDLE.init)
            defaults;
        auto h = CreateFileW(std.utf.toUTF16z(name), defaults);

        cenforce(h != INVALID_HANDLE_VALUE, name);
        scope(exit) cenforce(CloseHandle(h), name);
        auto size = GetFileSize(h, null);
        cenforce(size != INVALID_FILE_SIZE, name);
        size = min(upTo, size);
        auto buf = malloc(size + 1);
        assert(buf);
        scope(failure) free(buf);

        DWORD numread = void;
        cenforce(ReadFile(h, buf, size, &numread, null) == 1
                && numread == size, name);
        (cast(ubyte*)buf)[size] = 0;            // sentinel at end
        return buf[0 .. size];
    }
    else version(Posix)
    {
        // A few internal configuration parameters {
        enum size_t
            minInitialAlloc = 1024 * 4,
            maxInitialAlloc = size_t.max / 2,
            sizeIncrement = 1024 * 16,
            maxSlackMemoryAllowed = 1024;
        // }

        immutable fd = core.sys.posix.fcntl.open(toStringz(name),
                core.sys.posix.fcntl.O_RDONLY);
        cenforce(fd != -1, name);
        scope(exit) core.sys.posix.unistd.close(fd);

        stat_t statbuf = void;
        cenforce(fstat(fd, &statbuf) == 0, name);

        immutable initialAlloc = to!size_t(statbuf.st_size
            ? min(statbuf.st_size + 1, maxInitialAlloc)
            : minInitialAlloc);

        auto result = malloc(initialAlloc);
        assert(result);
        size_t result_length = initialAlloc;
        scope(failure) free(result);
        size_t size = 0;

        for (;;)
        {
            immutable actual = core.sys.posix.unistd.read(fd, result + size,
                    min(result_length, upTo) - size);
            cenforce(actual != -1, name);
            if (actual == 0) break;
            size += actual;
            if (size < result_length) continue;
            immutable newAlloc = size + sizeIncrement;
            result = realloc(result, newAlloc);
            assert(result);
            result_length = newAlloc;
        }

        return result_length - size >= maxSlackMemoryAllowed
            ? realloc(result, size)[0 .. size]
            : result[0 .. size];
    }
}
