
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import main;

import std.stdio;
import core.stdc.stdlib;
import std.format;
import std.range;
import std.path;

/******************************************
 * Parse the command line.
 * Input:
 *      args arguments from command line
 * Returns:
 *      Params filled in
 */

Params parseCommandLine(string[] args)
{
    import std.getopt;

    if (args.length == 1)
    {
        writeln(
"C Preprocessor
Copyright (c) 2013 by Digital Mars
All Rights Reserved
Options:
  filename...       source file name(s)
  -D macro[=value]  define macro
  --dep filename    generate dependencies to output file
  -I path           path to #include files
  -isystem path     path to system #include files
  -o filename       preprocessed output file
");
        exit(EXIT_SUCCESS);
    }

    Params p;

    getopt(args,
        std.getopt.config.passThrough,
        std.getopt.config.caseSensitive,
        "include|I",    &p.includes,
        "define|D",     &p.defines,
        "isystem",      &p.sysincludes,
        "dep",          &p.depFilename,
        "output|o",     &p.outFilenames);

    p.sourceFilenames = args[1 .. $];

    if (p.outFilenames.length == 0)
    {
        /* Output file names are not supplied, so build them by
         * stripping any .c or .cpp extension and appending .i
         */
        foreach (filename; p.sourceFilenames)
        {
            string outname;
            if (extension(filename) == ".c")
                outname = baseName(filename, ".c");
            else if (extension(filename) == ".cpp")
                outname = baseName(filename, ".cpp");
            else
                outname = baseName(filename);
            p.outFilenames ~= outname ~ ".i";
        }
    }

    /* Check for errors
     */
    if (p.sourceFilenames.length == p.outFilenames.length)
    {
        auto s = chain(p.sourceFilenames, p.outFilenames, [p.depFilename]);
        while (!s.empty)
        {
            auto name = s.front;
            s.popFront();
            foreach (name2; s.save)
            {
                if (name == name2)
                {
                    writefln("Error: duplicate file names %s and %s", name, name2);
                    exit(EXIT_FAILURE);
                }
            }
        }
    }
    else
    {
        writeln(p.sourceFilenames);
        writefln("Error: %s source files, but %s output files", p.sourceFilenames.length, p.outFilenames.length);
        exit(EXIT_FAILURE);
    }

    return p;
}

unittest
{
    auto p = parseCommandLine([
        "dmpp",
        "foo.c",
        "-D", "macro=value",
        "--dep", "out.dep",
        "-I", "path1",
        "-I", "path2",
        "--isystem", "sys1",
        "--isystem", "sys2",
        "-o", "out.i"]);

        assert(p.sourceFilenames == ["foo.c"]);
        assert(p.defines == ["macro=value"]);
        assert(p.depFilename == "out.dep");
        assert(p.includes == ["path1", "path2"]);
        assert(p.sysincludes == ["sys1", "sys2"]);
        assert(p.outFilenames == ["out.i"]);
}
