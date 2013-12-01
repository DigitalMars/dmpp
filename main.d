
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import std.stdio;
import core.stdc.stdlib;
import core.memory;

import cmdline;
import context;

alias char uchar;
alias immutable(uchar)[] ustring;

int main(string[] args)
{
    // No need to collect
    GC.disable();

    const params = parseCommandLine(args);

    auto context = Context(params);

    // Preprocess each file
    foreach (sourceFilename ; params.sourceFilenames)
    {
        context.localStart(sourceFilename);
        context.preprocess();
        context.localFinish();
    }

    context.globalFinish();

    return EXIT_SUCCESS;
}


void err_fatal(T...)(T args)
{
    stderr.write("Error: ");
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}

