
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module skip;

import std.range;
import std.ascii;
import std.traits;

import std.stdio;
import core.stdc.stdio;

import ranges;

void defaultError(T...)(T args)
{
    import std.stdio;
    import core.stdc.stdlib;

    stderr.write("Error: ");
    stderr.writefln(args);
    exit(EXIT_FAILURE);
}

version (unittest)
{
    bool err;
    void unittestError(T...)(T args) { err = true; }
}

/**************
 * Skip C++ style comment.
 * Input:
 *      R       range is on first character past //
 * Returns:
 *      range starting at beginning of next line
 */

R skipCppComment(alias error = defaultError, R)(R r) if (isInputRange!R)
{
    while (!r.empty)
    {
        auto c = r.front;
        r.popFront();
        if (c == '\n')
            return r;
    }
    error("// comment is not closed with newline");
    return r;
}

unittest
{
    auto r = "456\n89".skipCppComment();
    assert(!r.empty && r.front == '8');

    err = false;
    r = "45689".skipCppComment!unittestError();
    assert(err);
}

/**************
 * Skip C style comment.
 * Input:
 *      R       range is on first character past / *
 * Returns:
 *      range starting after closing * /
 */

R skipCComment(alias error = defaultError, R)(R r) if (isInputRange!R)
{
    bool star;
    while (!r.empty)
    {
        auto c = r.front;
        r.popFront();
        switch (c)
        {
            case '*':
                star = true;
                break;

            case '/':
                if (star)
                    return r;
            default:
                star = false;
                break;
        }
    }
    error("/* comment is not closed with */");
    return r;
}

unittest
{
    string s = "45/*6* /*/89";
    auto r = s.skipCComment();
    assert(!r.empty && r.front == '8');
}

/****************************
 * Skip character literal.
 * Input:
 *      R       range is on first character past '
 * Returns:
 *      range starting after closing '
 */

R skipCharacterLiteral(alias error = defaultError, R, S)(R r, ref S s)
        if (isInputRange!R && isOutputRange!(S,ElementEncodingType!R))
{
    bool slash;
    while (!r.empty)
    {
        auto c = cast(ElementEncodingType!R)r.front;
        s.put(c);
        r.popFront();
        switch (c)
        {
            case '\\':
                slash = !slash;
                break;

            case '\'':
                if (!slash)
                    return r;
            default:
                slash = false;
                break;
        }
    }
    error("character literal is not closed with '");
    return r;
}

unittest
{
    BitBucket!char b = void;

    string s = "456\\\\'x";
    auto r = s.skipCharacterLiteral(b);
    assert(!r.empty && r.front == 'x');

    StaticArrayBuffer!(char,100) a = void;
    a.init();

    r = "asdf\\'a'b".skipCharacterLiteral(a);
    assert(!r.empty && r.front == 'b');
    assert(a[] == "asdf\\'a'");
}


/****************************
 * Skip string literal.
 * Input:
 *      R       range is on first character past "
 * Returns:
 *      range starting after closing "
 */

R skipStringLiteral(alias error = defaultError, R, S)(R r, ref S s)
        if (isInputRange!R && isOutputRange!(S,ElementEncodingType!R))
{
    bool slash;
    while (!r.empty)
    {
        auto c = cast(ElementEncodingType!R)r.front;
        s.put(c);
        r.popFront();
        switch (c)
        {
            case '\\':
                slash = !slash;
                break;

            case '"':
                if (!slash)
                    return r;
            default:
                slash = false;
                break;
        }
    }
    error("string literal is not closed with \"");
    return r;
}

unittest
{
    BitBucket!char b = void;

    string s = "456\\\\\"x";
    auto r = s.skipStringLiteral(b);
    assert(!r.empty && r.front == 'x');

    StaticArrayBuffer!(char,100) a = void;
    a.init();

    r = "asdf\\\"a\"b".skipStringLiteral(a);
    assert(!r.empty && r.front == 'b');
//writefln("a = |%s|", a[]);
    assert(a[] == "asdf\\\"a\"");
}


/**************
 * Skip raw string literal.
 * Input:
 *      R       range is on first character past R"
 * Returns:
 *      range starting after closing "
 */

R skipRawStringLiteral(alias error = defaultError, R, S)(R r, ref S s)
        if (isInputRange!R && isOutputRange!(S,ElementEncodingType!R))
{
    enum RAW { start, string, end }

    RAW rawstate = RAW.start;

    alias Unqual!(ElementEncodingType!R) E;
    E[16 + 1] dcharbuf = void;
    size_t dchari = 0;

    while (!r.empty)
    {
        auto c = cast(E)r.front;
        s.put(c);
        r.popFront();

        final switch (rawstate)
        {
            case RAW.start:
                if (c == '(')       // end of d-char-string
                {
                    dcharbuf[dchari] = 0;
                    rawstate = RAW.string;
                }
                else if (c == ' '  || c == '('  || c == ')'  ||
                         c == '\\' || c == '\t' || c == '\v' ||
                         c == '\f' || c == '\n')
                {
                    error("invalid dchar '%s'", c);
                    return r;
                }
                else if (dchari >= dcharbuf.length)
                {
                    error("dchar string maximum of %s is exceeded", dcharbuf.length);
                    return r;
                }
                else
                {
                    dcharbuf[dchari] = c;
                    ++dchari;
                }
                break;

            case RAW.string:
                if (c == ')')
                {
                    dchari = 0;
                    rawstate = RAW.end;
                }
                break;

            case RAW.end:
                if (c == dcharbuf[dchari])
                {
                    ++dchari;
                }
                else if (dcharbuf[dchari] == 0)
                {
                    if (c == '"')
                        return r;
                    else
                        rawstate = RAW.string;
                }
                else if (c == ')')
                {
                    // Rewind ')' dcharbuf[0..dchari]
                    dchari = 0;
                }
                else
                {
                    // Rewind ')' dcharbuf[0..dchari]
                    rawstate = RAW.string;
                }
                break;
        }
    }
    error("raw string literal is not closed");
    return r;
}

unittest
{
    StaticArrayBuffer!(char,100) a = void;
    a.init();

    auto r = "a(bcd\")b\")a\"e".skipRawStringLiteral(a);
    assert(!r.empty && r.front == 'e');
    assert(a[] == "a(bcd\")b\")a\"");
}


/**************
 * Skip white space, where whitespace is:
 *      space, tab, carriage return, C comment, C++ comment
 * Input:
 *      R       range is on first character
 * Returns:
 *      range starting at first character following whitespace
 */

R skipWhitespace(alias error = defaultError, R)(R r) if (isInputRange!R)
{
    alias Unqual!(ElementType!R) E;

    E lastc = ' ';
    while (!r.empty)
    {
        E c = r.front;
        switch (c)
        {
            case ' ':
            case '\t':
            case '\r':
                break;

            case '/':
                if (lastc == '/')
                {
                    r.popFront();
                    r = r.skipCppComment!error();
                    c = ' ';
                    continue;
                }
                break;

            case '*':
                if (lastc == '/')
                {
                    r.popFront();
                    r = r.skipCComment!error();
                    c = ' ';
                    continue;
                }
                break;

            default:
                return r;
        }
        lastc = c;
        r.popFront();
    }
    return r;
}

unittest
{
    auto r = (cast(immutable(ubyte)[])" \t\r/* */8").skipWhitespace();
    assert(!r.empty && r.front == '8');

    r = (cast(immutable(ubyte)[])" // \n8").skipWhitespace();
    assert(!r.empty && r.front == '8');
}


/**************************************************
 * Reads in an identifier.
 * Output:
 *      s    OutputRange to write identifier to
 * Returns:
 *      range after identifier
 * BUGS: doesn't handle \u, \U or Unicode chars, doesn't do Unicode decoding
 */


R inIdentifier(R, S)(R r, ref S s)
        if (isInputRange!R && isOutputRange!(S,ElementEncodingType!R))
{
    while (!r.empty)
    {
        auto c = cast(ElementEncodingType!R)r.front;
        if (isAlphaNum(c) || c == '_')
        {
            s.put(c);
        }
        else
            break;
        r.popFront();
    }
    return r;
}

unittest
{
  {
    StaticArrayBuffer!(char, 1024) id = void;
    id.init();
    auto r = "abZ123_ 3".inIdentifier(id);
    assert(!r.empty && r.front == ' ' && id[] == "abZ123_");
  }
  {
    StaticArrayBuffer!(ubyte, 1024) id = void;
    id.init();
    auto r = (cast(immutable(ubyte)[])"abZ123_ 3").inIdentifier(id);
    assert(!r.empty && r.front == ' ' && id[] == "abZ123_");
  }
}

