
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
import directive;
import expanded;
import id;
import lexer;
import loc;
import macros;
import main;
import outdeps;
import textbuf;
import sources;

/*********************************
 * Keep the state of the preprocessor in this struct.
 * Input:
 *      R       output range for preprocessor output
 */

struct Context(R)
{
    const Params params;        // command line parameters

    string[] paths;     // #include paths
    size_t sysIndex;    // paths[sysIndex] is start of system #includes

    bool errors;        // true if any errors occurred
    uint counter;       // for __COUNTER__

    bool doDeps;        // true if doing dependency file generation
    string[] deps;      // dependency file contents

    Source[10] sources;
    int sourcei = -1;
    int sourceFilei = -1;

    uchar xc = ' ';

    Expanded!R expanded;         // for expanded (preprocessed) output

    Loc lastloc;
    bool uselastloc;

    __gshared Context* _ctx;            // shameful use of global variable

    // Stack of #if/#else/#endif nesting
    ubyte[8] tmpbuf = void;
    Textbuf!ubyte ifstack;


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

        ifstack = Textbuf!ubyte(tmpbuf);
        ifstack.initialize();
        expanded.initialize(&this);
        setContext();
    }

    static Context* getContext()
    {
        return _ctx;
    }

    void setContext()
    {
        _ctx = &this;
    }

    /**********
     * Create local context
     */
    void localStart(SrcFile* sf, R outrange)
    {
        // Define predefined macros
        Id.defineMacro(cast(ustring)"__BASE_FILE__", null, cast(ustring)sf.filename, Id.IDpredefined);
        Id.initPredefined();
        foreach (def; params.defines)
            macrosDefine(def);

        // Set up preprocessed output
        expanded.start(outrange);

        // Initialize source text
        pushFile(sf, false);
    }

    void pushFile(SrcFile* sf, bool isSystem)
    {
        auto s = push();
        sourceFilei = sourcei;
        s.addFile(sf, isSystem, -1);
        if (lastloc.srcFile)
            uselastloc = true;
    }

    /**********
     * Preprocess a file
     */
    void preprocess()
    {
        auto lexer = createLexer(&this);
        while (1)
        {
            // Either at start of a new line, or the end of the file
            assert(!lexer.empty);
            auto tok = lexer.front;
            if (tok == TOK.eol)
                lexer.popFront();
            else if (tok == TOK.hash)
            {
                // A '#' starting off a line says preprocessing directive
                if (lexer.parseDirective())
                {
                    auto csf = currentSourceFile();
                    if (csf)
                        csf.seenTokens = true;
                }
            }
            else if (tok == TOK.eof)
                break;
            else
            {
                auto csf = currentSourceFile();
                if (csf)
                    csf.seenTokens = true;

                do
                {
                    lexer.popFront();
                } while (lexer.front != TOK.eol);
                lexer.popFront();
            }
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
            dependencyFileWrite(params.depFilename, deps);
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

    uchar[] restOfLine()
    {
        auto s = &sources[sourcei];
        auto result = s.lineBuffer[s.texti .. s.lineBuffer.length];
        s.texti = s.lineBuffer.length;
        xc = '\n';
        return result;
    }

    void unget()
    {
        assert(sources[sourcei].texti);
        --sources[sourcei].texti;
    }

    void push(uchar c)
    {
        auto s = push();
        s.lineBuffer.initialize();
        s.lineBuffer.put(c);
        s.texti = 0;
    }

    void push(const(uchar)[] str)
    {
        auto s = push();
        s.lineBuffer.initialize();
        s.lineBuffer.put(str);
        s.texti = 0;
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
            if (s.includeGuard && !s.seenTokens)
            {
                // Saw #endif and no tokens
                s.loc.srcFile.includeGuard = s.includeGuard;
            }
        }
        --sourcei;
        return sourcei == -1 ? null : &sources[sourcei];
    }

    bool isExpanded() { return sources[sourcei].isExpanded; }

    void setExpanded() { sources[sourcei].isExpanded = true; }

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

    /*******************************************
     * Search for file along paths[]
     */
    SrcFile* searchForFile(bool includeNext, out bool isSystem, const(char)[] s)
    {
        int pathIndex = 0;
        if (isSystem)
        {
            pathIndex = sysIndex;
        }
        else
        {
            auto csf = currentSourceFile();
            if (csf && includeNext)
                pathIndex = csf.pathIndex;
        }

        auto sf = fileSearch(cast(string)s, paths, pathIndex, pathIndex);
        if (!sf)
            return null;

        if (sf.contents == null)
        {
            sf.read();
            if (!isSystem && doDeps)
                deps ~= sf.filename;
        }
        return sf;
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
    // These are if isFile is true
    Loc loc;            // current location
    ustring input;      // remaining file contents
    string includeGuard;
    int pathIndex;      // index into paths[] of where this file came from (-1 if not)
    int ifstacki;       // index into ifstack[]

    uchar[16] tmpbuf = void;
    Textbuf!uchar lineBuffer = void;

    uint texti;         // index of current position in lineBuffer[]

    bool isFile;        // if it is a file
    bool isExpanded;    // true if already macro expanded
    bool seenTokens;    // true if seen tokens

    void addFile(SrcFile* sf, bool isSystem, int pathIndex)
    {
        // set new file, set haven't seen tokens yet
        loc.srcFile = sf;
        loc.lineNumber = 0;
        loc.isSystem = isSystem;
        input = sf.contents;
        isFile = true;
        includeGuard = null;
        this.pathIndex = pathIndex;
        this.isExpanded = false;
        this.seenTokens = false;
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


/************************************** unit tests *************************/

version (unittest)
{
    void testPreprocess(const Params params, string src, string result)
    {

        uchar[100] tmpbuf = void;
        auto outbuf = Textbuf!uchar(tmpbuf);

        auto context = Context!(Textbuf!uchar*)(params);

        // Create a fake source file with contents
        auto sf = SrcFile.lookup("test.c");
        sf.contents = cast(ustring)src;

        context.localStart(sf, &outbuf);

        context.preprocess();

        context.expanded.finish();
        if (outbuf[] != result)
            writefln("output = |%s|", outbuf[]);
        assert(outbuf[] == result);
    }
}

version (none)
{
unittest
{
    const Params params;
    testPreprocess(params,
"asdf\r
asd\\\r
ff\r
",

`# 2 "test.c"
asdf
# 3 "test.c"
asdff
`);
}

unittest
{
    writeln("u2");
    Params params;
    params.defines ~= "abc=def";
    testPreprocess(params, "+abc+\n", "# 1 \"test.c\"\n+def+\n");
}
}

unittest
{
    writeln("u3");
    Params params;
    params.defines ~= "abc2(a)=def=a=*";
    testPreprocess(params, "+abc2(3)+\n", "# 1 \"test.c\"\n+def=3=* +\n");
//    exit(0);
}


