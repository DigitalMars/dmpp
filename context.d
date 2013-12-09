
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module context;

import core.stdc.stdio;
import core.stdc.stdlib;

import std.algorithm;
import std.array;
import std.path;
import std.range;
import std.stdio;
import std.traits;

import cmdline;
import expanded;
import id;
import loc;
import macros;
import main;
import textbuf;
import sources;

/*********************************
 * Keep the state of the preprocessor in this struct.
 */

struct Context
{
    const Params params;        // command line parameters

    string[] paths;     // #include paths
    size_t sysIndex;    // paths[sysIndex] is start of system #includes

    bool errors;        // true if any errors occurred
    uint counter;       // for __COUNTER__

    bool doDeps;        // true if doing dependency file generation
    char[] deps;        // dependency file contents

    Source[10] sources;
    int sourcei = -1;
    int sourceFilei = -1;

    uchar xc = ' ';

    Expanded expanded;

    Loc lastloc;
    bool uselastloc;

    __gshared Context *_ctx;            // shameful use of global variable

    /******
     * Construct global context from the command line parameters
     */
    this(ref const Params params)
    {
        this.params = params;
        this.doDeps = params.depFilename.length != 0;

        combineSearchPaths(params.includes, params.sysincludes, paths, sysIndex);

        foreach (i; 0 .. sources.length)
        {
            sources[i].lineBuffer = Textbuf!uchar(sources[i].tmpbuf);
        }

        expanded.initialize(&this);

        _ctx = &this;
    }

    Context* getContext()
    {
        return _ctx;
    }

    /**********
     * Create local context
     */
    void localStart(string sourceFilename, string outFilename)
    {
        writefln("from %s to %s", sourceFilename, outFilename);
        Id.defineMacro(cast(ustring)"__BASE_FILE__", null, cast(ustring)sourceFilename, Id.IDpredefined);
        Id.initPredefined();
        foreach (def; params.defines)
            macrosDefine(def);
        expanded.start(outFilename);
        auto s = push();
        sourceFilei = sourcei;
        s.addFile(sourceFilename, false);
        if (lastloc.srcFile)
            uselastloc = true;
    }

    /**********
     * Preprocess a file
     */
    void preprocess()
    {
        while (!empty)
        {
            auto c = front();
            popFront();
        }
    }

    /**********
     * Finish local context
     */
    void localFinish()
    {
        expanded.finish();
    }

    /**********
     * Finish global context
     */
    void globalFinish()
    {
        if (doDeps && !errors)
        {
            std.file.write(params.depFilename, deps);
        }
    }

    @property bool empty()
    {
        return xc == xc.init;
    }

    @property uchar front()
    {
        return xc;
    }

    void popFront()
    {
        while (1)
        {
            auto s = &sources[sourcei];
            if (s.texti < s.lineBuffer.length)
            {
                xc = s.lineBuffer[s.texti];
                ++s.texti;
            }
            else
            {
                if (s.isFile && !s.input.empty)
                {
                    s.readLine();
                    continue;
                }
                ++s.loc.lineNumber;
                s = pop();
                if (s)
                    continue;
                xc = xc.init;
                break;
            }
            expanded.put(xc);
            break;
        }
    }

    void unget()
    {
        assert(sources[sourcei].texti);
        --sources[sourcei].texti;
    }

    Source* currentSourceFile()
    {
        return sourceFilei == -1 ? null : &sources[sourceFilei];
    }

    Source* push()
    {
        ++sourcei;
        return &sources[sourcei];
    }

    Source* pop()
    {
        auto s = &sources[sourcei];
        if (s.isFile)
        {
            // Back up and find previous file; -1 if none
            if (sourceFilei == sourcei)
            {
                auto i = sourcei;
                while (1)
                {
                    --i;
                    if (i < 0 || sources[i].isFile)
                    {
                        sourceFilei = i;
                        break;
                    }
                }
            }
            lastloc = s.loc;
            uselastloc = true;
            if (s.includeGuard)
            {
                assert(0);              // fix
                //if (saw #endif and no tokens)
                    s.loc.srcFile.includeGuard = s.includeGuard;
            }
        }
        --sourcei;
        return sourcei == -1 ? null : &sources[sourcei];
    }

    /***************************
     * Return text associated with predefined macro.
     */
    ustring predefined(Id* m)
    {
        auto s = currentSourceFile();
        if (!s)
            return null;
        uint n;

        switch (m.flags & (Id.IDlinnum | Id.IDfile | Id.IDcounter))
        {
            case Id.IDlinnum:
                n = s.loc.lineNumber;
                break;

            case Id.IDfile:
                return s.loc.srcFile.filename;

            case Id.IDcounter:
                n = counter++;
                break;

            default:
                assert(0);
        }
        auto p = cast(uchar*)malloc(counter.sizeof * 3 + 1);
        assert(p);
        auto len = sprintf(cast(char*)p, "%u", n);
        assert(len > 0);
        return cast(ustring)p[0 .. len];
    }
}

/********************************************
 * Read a line of source from r and write it to the output range s.
 * Make sure line ends with \n
 */

R readLine(R, S)(R r, ref S s)
        if (isInputRange!R && isOutputRange!(S,ElementEncodingType!R))
{
    alias Unqual!(ElementEncodingType!R) E;

    while (1)
    {
        if (r.empty)
        {
            s.put('\n');
            break;
        }
        E c = cast(E)r.front;
        r.popFront();
        switch (c)
        {
            case '\r':
                continue;

            case '\n':
                s.put(c);
                break;

            default:
                s.put(c);
                continue;
        }
        break;
    }
    return r;
}


/******************************************
 * Source text.
 */

struct Source
{
    // Source file
    ustring input;      // text of the source file
    Loc loc;            // current location
    bool isFile;
    string includeGuard;

    uchar[1000] tmpbuf = void;
    Textbuf!uchar lineBuffer = void;

    size_t texti;       // index of current position in lineBuffer[]

    void addFile(string fileName, bool isSystem)
    {
        loc.srcFile = SrcFile.lookup(fileName);
        assert(loc.srcFile.filename == fileName);
        loc.lineNumber = 0;
        loc.isSystem = isSystem;
        input = cast(ustring)std.file.read(fileName);
        isFile = true;
        includeGuard = null;

        // set new file, set haven't seen tokens yet
    }

    /***************************
     * Read next line from input[] and store in lineBuffer[].
     * Do \ line splicing.
     */
    void readLine()
    {
        //writefln("Source.readLine() %d", loc.lineNumber);
        lineBuffer.initialize();

        while (!input.empty)
        {
            ++loc.lineNumber;
            input = input.readLine(lineBuffer);
            if (lineBuffer.length >= 2 &&
                lineBuffer[lineBuffer.length - 2] == '\\')
            {
                lineBuffer.pop();
                lineBuffer.pop();
            }
            else
                break;
        }
        texti = 0;

        assert(!lineBuffer.length || lineBuffer[lineBuffer.length - 1] == '\n');
        //writefln("\t%d", loc.lineNumber);
    }
}


