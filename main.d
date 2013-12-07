
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

version (unittest)
{
    int main() { writeln("unittests successful"); return EXIT_SUCCESS; }
}
else
{
    int main(string[] args)
    {
        // No need to collect
        GC.disable();

        const params = parseCommandLine(args);

        auto context = Context(params);

        // Preprocess each file
        foreach (i; 0 .. params.sourceFilenames.length)
        {
            context.localStart(params.sourceFilenames[i], params.outFilenames[i]);
            context.preprocess();
            context.localFinish();
        }

        context.globalFinish();

        return EXIT_SUCCESS;
    }
}


void err_fatal(T...)(T args)
{
    stderr.write("Error: ");
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}

