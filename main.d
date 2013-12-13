
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
import loc;
import sources;

alias char uchar;
alias immutable(uchar)[] ustring;

alias typeof(File.lockingTextWriter()) R;

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

        auto context = Context!R(params);

        // Preprocess each file
        foreach (i; 0 .. params.sourceFilenames.length)
        {
            auto srcFilename = params.sourceFilenames[i];
            auto outFilename = params.outFilenames[i];

            if (context.params.verbose)
                writefln("from %s to %s", srcFilename, outFilename);

            auto sf = SrcFile.lookup(srcFilename);
            if (!sf.read())
                err_fatal("cannot read file %s", srcFilename);

            if (context.doDeps)
                context.deps ~= srcFilename;

            File* fout = new File(outFilename, "wb");

            context.localStart(sf, fout.lockingTextWriter());
            context.preprocess();
            context.localFinish();

            delete fout;
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

void err_fatal(L:Loc, T...)(L loc, T args)
{
    loc.write(&stderr);
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}


