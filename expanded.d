
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
    Textbuf!(uchar,"exp") lineBuffer = void;

    R* foutr;

    int noexpand = 0;
    int lineNumber = 1;                 // line number of expanded output

    void off() { ++noexpand; }
    void on()  { --noexpand; assert(noexpand >= 0); }

    void initialize(Context!R* ctx)
    {
        this.ctx = ctx;
        lineBuffer = Textbuf!(uchar,"exp")(tmpbuf2);
    }

    void start(R* foutr)
    {
        this.foutr = foutr;
        this.lineBuffer.initialize();
        this.noexpand = 0;
        this.lineNumber = 1;
    }

    void finish()
    {
        put('\n');      // cause last line to be flushed to output
    }

    void put(uchar c)
    {
        //writefln("expanded.put('%c', %s)", c, noexpand);
        if (c != ESC.space && !noexpand)
        {
            if (lineBuffer.length && lineBuffer.last() == '\n')
                put2();
            //writefln("lineBuffer.put('%c')", c);
            lineBuffer.put(c);
        }
    }

    void put2()
    {
        if (lineBuffer[0] != '\n')
        {
            auto s = ctx.currentSourceFile();
            if (s)
            {
                auto linnum = s.loc.lineNumber - 1;
                if (!ctx.lastloc.srcFile || ctx.lastloc.srcFile != s.loc.srcFile)
                {
                    if (ctx.uselastloc)
                    {
//writeln("test1");
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
//writeln("test2");
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
//writeln("test3");
                            s.loc.linemarker(foutr);
                        }
                    }
                }
                lineNumber = linnum;
            }
            else if (ctx.uselastloc && ctx.lastloc.srcFile)
            {
//writeln("test4");
                ctx.lastloc.linemarker(foutr);
            }
        }
        ctx.uselastloc = false;
        lineBuffer.put(0);              // add sentinel
        foutr.writePreprocessedLine(lineBuffer[]);
        lineBuffer.initialize();
        ++lineNumber;
    }

    void put(ustring s)
    {
        //writefln("expanded.put('%s')", cast(string)s);
        /* This will always be an identifier string, so we can skip
         * a lot of the checking.
         */
        if (!noexpand)
        {
            if (s.length > 0)
            {
                put(s[0]);
                if (s.length > 1)
                    lineBuffer.put(s[1 .. $]);
            }
        }
    }

    /*******************
     * Remove last character emitted.
     */
    void popBack()
    {
        if (!noexpand && lineBuffer.length)
            lineBuffer.pop();
    }

    /****************************
     * Erase current unemitted line.
     */
    void eraseLine()
    {
        lineBuffer.initialize();
    }
}


