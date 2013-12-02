
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module cmdline;

import main;

import std.stdio;
import std.range;
import std.path;
import std.array;
import std.algorithm;

import core.stdc.stdlib;

/*********************
 * Initialized with the command line arguments.
 */
struct Params
{
    string[] sourceFilenames;
    string[] outFilenames;
    string depFilename;
    string[] defines;
    string[] includes;
    string[] sysincludes;
}


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
  --isystem path    path to system #include files
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
        // Look for duplicate file names
        auto s = chain(p.sourceFilenames, p.outFilenames, (&p.depFilename)[0..1]).
                 array.
                 sort!((a,b) => filenameCmp(a,b) < 0).
                 findAdjacent!((a,b) => filenameCmp(a,b) == 0);
        if (!s.empty)
        {
            err_fatal("duplicate file names %s", s.front);
        }
    }
    else
    {
        err_fatal("%s source files, but %s output files", p.sourceFilenames.length, p.outFilenames.length);
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
