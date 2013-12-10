
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module expanded;

import std.stdio;

import context;
import macros;
import main;
import textbuf;

/******************************************
 * Expanded output.
 */

struct Expanded(R)
{
    Context!R* ctx;

    // Expanded output file
    uchar[1000] tmpbuf2 = void;
    Textbuf!uchar lineBuffer = void;

    R foutr;

    int noexpand = 0;
    int lineNumber = 1;                 // line number of expanded output

    void off() { ++noexpand; }
    void on()  { --noexpand; assert(noexpand >= 0); }

    void initialize(Context!R* ctx)
    {
        this.ctx = ctx;
        lineBuffer = Textbuf!uchar(tmpbuf2);
    }

    void start(R foutr)
    {
        this.foutr = foutr;
        lineBuffer.initialize();
    }

    void finish()
    {
        put('\n');      // cause last line to be flushed to output
    }

    void put(uchar c)
    {
        if (c != ESC.space && !noexpand)
        {
            if (lineBuffer.length && lineBuffer.last() == '\n')
            {

                auto s = ctx.currentSourceFile();
                if (s)
                {
                    auto linnum = s.loc.lineNumber - 1;
                    if (!ctx.lastloc.srcFile || ctx.lastloc.srcFile != s.loc.srcFile)
                    {
                        if (ctx.uselastloc)
                        {
                            ctx.lastloc.linemarker(foutr);
                        }
                        else
                        {
                            /* Since the next readLine() has already been called,
                             * s.loc.lineNumber is one ahead of the expanded line
                             * that has yet to be written out. So linemarker() subtracts
                             * one to compensage.
                             * However, if the next readLine() read a \ line spliced line,
                             * s.loc.lineNumber may be further ahead than just one.
                             * This, then, is a bug.
                             */
                            s.loc.linemarker(foutr);
                            ctx.lastloc = s.loc;
                        }
                    }
                    else if (linnum != lineNumber)
                    {
                        if (linnum == lineNumber + 1)
                            lineBuffer.put('\n');
                        else
                        {
                            if (lineNumber + 30 < linnum)
                            {
                                foreach (i; lineNumber .. linnum)
                                    lineBuffer.put('\n');
                            }
                            else
                            {
                                s.loc.linemarker(foutr);
                            }
                        }
                    }
                    lineNumber = linnum;
                }
                else if (ctx.uselastloc && ctx.lastloc.srcFile)
                {
                    ctx.lastloc.linemarker(foutr);
                }

                ctx.uselastloc = false;
                foutr.writePreprocessedLine(lineBuffer[]);
                lineBuffer.initialize();
                ++lineNumber;
            }
            lineBuffer.put(c);
        }
    }

    void put(ustring s)
    {
        foreach (uchar c; s)
            put(c);
    }

    /*******************
     * Remove last character emitted.
     */
    void popBack()
    {
        if (!noexpand && lineBuffer.length)
            lineBuffer.pop();
    }
}


