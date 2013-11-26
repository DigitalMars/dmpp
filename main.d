
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import std.stdio;
import core.stdc.stdlib;

struct Params
{
    string sourceFilename;
    string outFilename;
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


Params parseCommandLine(string[] args)
{
    import std.getopt;

    if (args.length == 1)
    {
        writeln(
"C Preprocessor
Copyright (c) 2013 by Digital Mars
All Rights Reserved
Usage:
");
    }

    Params p;
    return p;
}
