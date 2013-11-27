
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import std.stdio;
import core.stdc.stdlib;

import cmdline;

struct Params
{
    string[] sourceFilenames;
    string[] outFilenames;
    string depFilename;
    string[] defines;
    string[] includes;
    string[] sysincludes;
}

int main(string[] args)
{
    auto params = parseCommandLine(args);
    return EXIT_SUCCESS;
}


void err_fatal(T...)(T args)
{
    stderr.write("Error: ");
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}
