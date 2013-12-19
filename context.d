
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

//debug=ContextStats;

struct Context(R)
{
    const Params params;      // command line parameters

    const string[] paths;     // #include paths
    const size_t sysIndex;    // paths[sysIndex] is start of system #includes

    bool errors;        // true if any errors occurred
    __gshared uint counter;       // for __COUNTER__

    bool doDeps;        // true if doing dependency file generation
    string[] deps;      // dependency file contents

    Source[4] sources;  // rare that more than 4 is needed by macroExpand()
    Source* psource;
    Source* psourceFile;

    debug (ContextStats)
    {
        int sourcei;
        int sourceimax;
    }

    uchar xc = ' ';

    Expanded!R expanded;         // for expanded (preprocessed) output

    Loc lastloc;
    bool uselastloc;

    __gshared Context* _ctx;            // shameful use of global variable
    Context* prev;                      // previous one in stack of these

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

        string[] pathsx;
        combineSearchPaths(params.includes, params.sysincludes, pathsx, sysIndex);
        paths = pathsx;         // workaround for Bugzilla 11743

        Source.initialize(sources, null, null);

        ifstack = Textbuf!ubyte(tmpbuf);
        ifstack.initialize();
        expanded.initialize(&this);
        setContext();
    }

    /**************************************
     * Create a new Context on a stack of them.
     */
    Context* pushContext()
    {
        auto ctx = new Context(params);
        ctx.psourceFile = psourceFile;
        ctx.prev = &this;
        ctx.expanded.off();
        return ctx;
    }

    Context* popContext()
    {
        prev.setContext();
        return prev;
    }

    /***************************
     * Reset to use again.
     */
    void reset()
    {
        Id.reset();
        SrcFile.reset();

        counter = 0;
        ifstack.initialize();
        xc = ' ';
        lastloc = lastloc.init;
        uselastloc = false;
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
    void localStart(SrcFile* sf, R* outrange)
    {
        // Define predefined macros
        Id.defineMacro(cast(ustring)"__BASE_FILE__", null, cast(ustring)sf.filename, Id.IDpredefined);
        Id.initPredefined();
        foreach (def; params.defines)
            macrosDefine(cast(ustring)def);

        // Set up preprocessed output
        expanded.start(outrange);

        // Initialize source text
        pushFile(sf, false, -1);
    }

    void pushFile(SrcFile* sf, bool isSystem, int pathIndex)
    {
        //write("pushFile ", pathIndex);
        auto s = push();
        psourceFile = s;
        s.addFile(sf, isSystem, pathIndex);
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
                    {
                        csf.seenTokens = true;
                    }
                }
            }
            else if (tok == TOK.eof)
                break;
            else
            {
                auto csf = currentSourceFile();
                if (csf)
                {
                    csf.seenTokens = true;
                }

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

        debug (ContextStats)
        {
            writefln("max Source depth = %d", sourceimax);
        }
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
            auto s = psource;
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
        auto s = psource;
        auto result = s.lineBuffer[s.texti .. s.lineBuffer.length];
        s.texti = cast(uint)s.lineBuffer.length;
        xc = '\n';
        return result;
    }

    void unget()
    {
        if (psource && psource.texti)
        {
            --psource.texti;
            assert(psource.lineBuffer[psource.texti] == xc);
        }
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
        return psourceFile;
    }

    Loc loc()
    {
        auto csf = currentSourceFile();
        if (csf)
            return csf.loc;
        if (lastloc.srcFile)
            return lastloc;
        Loc loc;
        return loc;
    }

    Source* push()
    {
        auto s = psource;
        if (s)
        {
            s = s.next;
            if (!s)
            {
                // Ran out of space, allocate another chunk
                auto sources2 = new Source[16];
                Source.initialize(sources2, psource, &psource.next);
                s = psource.next;
                assert(s);
            }
        }
        else
            s = sources.ptr;
        s.isFile = false;
        s.isExpanded = false;
        s.seenTokens = false;
        psource = s;

        debug (ContextStats)
        {
            ++sourcei;
            if (sourcei > sourceimax)
                sourceimax = sourcei;
        }

        return s;
    }

    Source* pop()
    {
        auto s = psource;
        if (s.isFile)
        {
            // Back up and find previous file; null if none
            if (psourceFile == s)
            {
                for (auto ps = s; 1;)
                {
                    ps = ps.prev;
                    if (!ps || ps.isFile)
                    {
                        psourceFile = ps;
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
        psource = psource.prev;
        debug (ContextStats)
        {
            --sourcei;
        }
        return psource;
    }

    int nestLevel()
    {
        int level = -1;
        auto csf = currentSourceFile();
        while (csf)
        {
            if (csf.isFile)
                ++level;
            csf = csf.prev;
        }
        return level;
    }

    bool isExpanded() { return psource.isExpanded; }

    void setExpanded() { psource.isExpanded = true; }

    /***************************
     * Return text associated with predefined macro.
     */
    ustring predefined(Id* m)
    {
        Loc loc;
        auto s = currentSourceFile();
        if (s)
            loc = s.loc;
        else
            loc = lastloc;
        if (!loc.srcFile)
            return null;

        uint n;

        switch (m.flags & (Id.IDlinnum | Id.IDfile | Id.IDcounter))
        {
            case Id.IDlinnum:
                n = loc.lineNumber;
                break;

            case Id.IDfile:
                return cast(ustring)('"' ~ loc.srcFile.filename ~ '"');

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
     * Output:
     *  pathIndex       index of where file was found
     *  isSystem        set to true if file is found in -isystem paths
     */
    SrcFile* searchForFile(bool includeNext, bool curdir, ref bool isSystem, const(char)[] s, out int pathIndex)
    {
        //writefln("searchForFile(includeNext = %s, curdir = %s, isSystem = %s, s = '%s')", includeNext, curdir, isSystem, s);
        string currentPath;
        auto csf = currentSourceFile();

        if (curdir && csf)
            currentPath = dirName(csf.loc.srcFile.filename);

        if (isSystem)
        {
            if (csf && includeNext)
                pathIndex = csf.pathIndex + 1;
            else
                pathIndex = 0; //cast(int)sysIndex;
        }
        else
        {
            if (csf && includeNext)
                pathIndex = csf.pathIndex + 1;
            else
                pathIndex = 0;
        }

        auto sf = fileSearch(cast(string)s, paths, pathIndex, pathIndex, currentPath);
        if (!sf)
            return null;

        //writefln("path = %d sys = %d length = %d", pathIndex, sysIndex, paths.length);
        if (pathIndex >= sysIndex && pathIndex < paths.length)
            isSystem = true;

        if (!sf.cachedRead)
        {
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
    // Double linked list of stack of Source's
    Source* prev;
    Source* next;

    // These are if isFile is true
    Loc loc;            // current location
    ustring input;      // remaining file contents
    ustring includeGuard;
    int pathIndex;      // index into paths[] of where this file came from (-1 if not)
    int ifstacki;       // index into ifstack[]

    uchar[256] tmpbuf = void;
    Textbuf!uchar lineBuffer = void;

    uint texti;         // index of current position in lineBuffer[]

    bool isFile;        // if it is a file
    bool isExpanded;    // true if already macro expanded
    bool seenTokens;    // true if seen tokens

    /*****
     * Instead of constructing them individually, do them as a group,
     * necessary to sew together the linked list.
     */
    static void initialize(Source[] sources, Source* prev, Source** pNext)
    {
        foreach (ref src; sources)
        {
            src.prev = prev;
            prev = &src;

            if (pNext)
                *pNext = &src;
            pNext = &src.next;
            src.next = null;

            src.lineBuffer = Textbuf!uchar(src.tmpbuf);
        }
    }

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

        auto context = Context!(Textbuf!uchar)(params);

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

version (all)
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


