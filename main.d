
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import std.array;
import std.format;
import std.stdio;
import core.stdc.stdlib;
import core.memory;

import cmdline;
import context;
import loc;
import sources;

// Data type for C source code characters
alias ubyte uchar;
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

        try
        {
            // Preprocess each file
            foreach (i; 0 .. params.sourceFilenames.length)
            {
                if (i)
                    context.reset();

                auto srcFilename = params.sourceFilenames[i];
                auto outFilename = params.outFilenames[i];

                if (context.params.verbose)
                    writefln("from %s to %s", srcFilename, outFilename);

                auto sf = SrcFile.lookup(srcFilename);
                if (!sf.read())
                    err_fatal("cannot read file %s", srcFilename);

                if (context.doDeps)
                    context.deps ~= srcFilename;

                auto fout = File(outFilename, "wb");        // has destructor
                auto foutr = fout.lockingTextWriter();      // has destructor

                context.localStart(sf, &foutr);
                context.preprocess();
                context.localFinish();

                /* The one source file we don't need to cache the contents
                 * of is the .c file.
                 */
                sf.freeContents();
            }
        }
        catch (Exception e)
        {
            err_fatal(context.loc(), e.msg);
        }

        context.globalFinish();

        return EXIT_SUCCESS;
    }
}


void err_fatal(T...)(T args)
{
    auto app = appender!string();
    app.formattedWrite(args);
    throw new Exception(app.data);
}

void err_fatal(L:Loc, T...)(L loc, T args)
{
    loc.write(&stderr);
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}


