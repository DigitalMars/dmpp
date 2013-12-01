
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module macros;

import std.stdio;
import std.algorithm;
import std.array;
import std.ascii;
import core.stdc.stdlib;
import core.stdc.string;

import main;
import skip;
import textbuf;
import id;
import ranges;

bool isIdentifierStart(uchar c)
{
    return isAlpha(c) || c == '_';
}

bool isIdentifierChar(uchar c)
{
    return isAlphaNum(c) || c == '_';
}

// Embedded escape sequence commands
enum ESC : ubyte
{
    start     = '\x00',  // 0 can never appear in legit input, so this is the start
    arg1      = '\x01',
    concat    = '\xFF',
    stringize = '\xFE',
    space     = '\xFD',
    brk       = '\xFC',  // separate adjacent tokens
    expand    = '\xFB',
}

/************************************
 * Transform the macro replacement text into a replacement list.
 * Embed escape sequence commands for argument substitution, argument stringizing,
 * and token concatenation.
 * Input:
 *      objectLike      true if object-like macro, false if function-like
 *      parameters      macro parameters
 *      text            Original text; must end with \n
 * Returns:
 *      replacement list with embedded commands for inserting arguments and stringizing
 */

ustring macroReplacementList(bool objectLike, ustring[] parameters, ustring text)
{
    assert(text.length && text[$ - 1] == '\n');

    uchar[1000] tmpbuf = void;
    auto outbuf = Textbuf!uchar(tmpbuf);
    outbuf.put(0);

    while (1)
    {   uchar c = text[0];
        text = text[1 .. $];
        switch (c)
        {
            case '\t':
                c = ' ';
            case ' ':
                if (outbuf.length == 1 ||       // no leading whitespace
                    outbuf.last() == ' ')       // collapse adjacent whitespace into one ' '
                    continue;
                break;

            case '\n':                          // reached the end of the input
                if (outbuf.last() == ' ')
                    outbuf.pop();               // no trailing whitespace
                if (outbuf.last() == ESC.concat && outbuf[outbuf.length - 2] == ESC.start)
                    err_fatal("## cannot appear at end of macro text");
                return outbuf[1 .. outbuf.length].idup;

            case '\r':
                continue;

            case '"':
                /* Skip over character literals and string literals without
                 * examining their insides
                 */
                if (outbuf.last() == 'R')
                {
                    outbuf.put(c);
                    text = text.skipRawStringLiteral(outbuf);
                }
                else
                {
                    outbuf.put(c);
                    text = text.skipStringLiteral(outbuf);
                }
                continue;

            case '\'':
                outbuf.put(c);
                text = text.skipCharacterLiteral(outbuf);
                continue;

            case '/':
                if (outbuf.last() == '/')
                {   // C++ style comments end the input
                    text.skipCppComment();
                    outbuf.pop();
                    goto case '\n';
                }
                break;

            case '*':
                if (outbuf.last() == '/')
                {   // C style comments are treated as a single ' '
                    text = text.skipCComment();
                    outbuf.pop();
                    goto case '\t';
                }
                break;


            case '#':
                if (text[0] == '#')
                {
                    /* The ## token concatenation operator.
                     * Remove leading and trailing spaces, replace with ESC.start ESC.concat
                     */
                    if (outbuf.last() == ' ')
                        outbuf.pop();
                    if (outbuf.length == 1)
                        err_fatal("## cannot appear at beginning of macro text");
                    outbuf.put(ESC.start);
                    outbuf.put(ESC.concat);
                    text = text[1 .. $].skipWhitespace();
                    continue;
                }
                else if (!objectLike)
                {
                    /* The # stringize operator, parameter must immediately follow
                     */
                    text = text.skipWhitespace();
                    StaticArrayBuffer!(uchar, 1024) id = void;
                    id.init();
                    text = text.inIdentifier(id);
                    auto argi = countUntil(parameters, id[]);
                    if (argi == -1)
                        err_fatal("# must be followed by parameter");
                    else
                    {
                        outbuf.put(ESC.start);
                        outbuf.put(ESC.stringize);
                        outbuf.put(cast(uchar)(argi + 1));
                    }
                    continue;
                }
                break;

            default:
                if (parameters.length && isIdentifierStart(c))
                {
                    StaticArrayBuffer!(uchar, 1024) id = void;
                    id.init();
                    id.put(c);
                    text = text.inIdentifier(id);
                    auto argi = countUntil(parameters, id[]);
                    if (argi == -1)
                    {
                        outbuf.put(id[]);
                    }
                    else
                    {
                        outbuf.put(ESC.start);
                        outbuf.put(cast(uchar)(argi + 1));
                    }
                    continue;
                }
                break;
        }
        outbuf.put(c);
    }
    assert(0);
}

unittest
{
    ustring s;
    s = macroReplacementList(true, null, "\n");
    assert(s == "");
    s = macroReplacementList(true, null, " \t/*hello*/ //\n");
    assert(s == "");
    s = macroReplacementList(true, null, "# \n");
    assert(s == "#");
    s = macroReplacementList(true, null, "a ## /**/z\n");
    assert(s == "a" ~ ESC.start ~ ESC.concat ~ "z");
    s = macroReplacementList(false, ["abc"], "x#/**/abc y\n");
//writefln("'%s', %s", s, s.length);
    assert(s == "x" ~ ESC.start ~ ESC.stringize ~ ESC.arg1 ~ " y");
    s = macroReplacementList(false, ["abc"], "x  abc/**/y\n");
    assert(s == "x " ~ ESC.start ~ ESC.arg1 ~ " y");
    s = macroReplacementList(false, ["abc","a"], "x \"abc\" R\"a(abc)a\" 'a' \ry\n");
    assert(s == "x \"abc\" R\"a(abc)a\" 'a' y");
}

/***********************************************
 * Remove leading and trailing whitespace (' ' and ESC.brk).
 * Leave ESC.space intact.
 * Returns:
 *      modified input
 */

uchar[] trimWhiteSpace(uchar[] text)
{
    // Remove leading
    size_t fronti;
    size_t frontn;
    while (fronti < text.length)
    {
        switch (text[fronti])
        {
            case ' ':
            case ESC.brk:
                ++fronti;
                continue;

            case ESC.space:
                ++frontn;
                ++fronti;
                continue;

            default:
                break;
        }
        break;
    }

    // Remove trailing
    size_t backi = text.length;
    size_t backn;
    while (backi > fronti + 1)
    {
        switch (text[backi - 1])
        {
            case ' ':
            case ESC.brk:
                --backi;
                continue;

            case ESC.space:
                ++backn;
                --backi;
                continue;

            default:
                break;
        }
        break;
    }

    if (frontn)
        text[fronti - frontn .. fronti] = ESC.space;
    if (backn)
        text[backi .. backi + backn] = ESC.space;

    //writefln("frontn %d fronti %d backi %d backn %d", frontn, fronti, backn, backi);
    return text[fronti - frontn .. backi + backn];
}

unittest
{
    uchar[0] a;
    auto s = trimWhiteSpace(a);
    assert(s == "");

    uchar[1] b = " ";
    s = trimWhiteSpace(b);
    assert(s == "");

    ubyte[6] c = cast(ubyte[])("" ~ ESC.brk ~ " a " ~ ESC.brk ~ " ");
    s = trimWhiteSpace(cast(uchar[])c);
    assert(s == "a");

    ubyte[6] d = cast(ubyte[])("" ~ ESC.space ~ " a " ~ ESC.space ~ " ");
    s = trimWhiteSpace(cast(uchar[])d);
    assert(s == x"FD 61 FD");

    ubyte[1] e = cast(ubyte[])("" ~ ESC.space ~ "");
    s = trimWhiteSpace(cast(uchar[])e);
    assert(s == x"FD");

    ubyte[8] f = cast(ubyte[])("" ~ ESC.space ~ " ab " ~ ESC.space ~ "" ~ ESC.space ~ " ");
    s = trimWhiteSpace(cast(uchar[])f);
//writefln("'%s', %s", s, s.length);
    assert(s == x"FD 61 62 FD FD");

}

/******************************************
 * Remove all ESC.space and ESC.brk markers.
 * Remove all leading and trailing whitespace.
 * All done in-place.
 */

uchar[] trimEscWhiteSpace(uchar[] text)
{
    auto p = text.ptr;
    bool leading = true;

    foreach (uchar c; text)
    {
        switch (c)
        {
            case ESC.space:
            case ESC.brk:
                continue;

            case ' ':
                if (leading)
                    continue;
                break;

            default:
                leading = false;
                break;
        }
        *p++ = c;
    }

    while (p > text.ptr && p[-1] == ' ')
    {
        --p;
    }

    return text[0 .. p - text.ptr];
}

unittest
{
    ubyte[11] a = cast(ubyte[])("" ~ ESC.space ~ " a" ~ ESC.brk ~ " " ~ ESC.space ~ "b " ~ ESC.space ~ "" ~ ESC.space ~ " ");
    auto s = trimEscWhiteSpace(cast(uchar[])a);
//writefln("'%s', %s", s, s.length);
    assert(s == "a b");
}


/*************************************
 * Stringize the argument of the # operator per C99 6.10.3.2.2
 * Returns:
 *      a malloc'd ustring
 */

uchar[] stringize(const(uchar)[] text)
{
    // Remove leading spaces
    size_t i;
    for (; i < text.length; ++i)
    {
        auto c = text[i];
        if (!(c == ' ' || c == ESC.space || c == ESC.brk))
            break;
    }
    text = text[i .. $];

    // Remove trailing spaces
    for (i = text.length; i; --i)
    {
        auto c = text[i - 1];
        if (!(c == ' ' || c == ESC.space || c == ESC.brk))
            break;
    }
    text = text[0 .. i];

    uchar[1000] tmpbuf = void;
    auto outbuf = Textbuf!uchar(tmpbuf);
    outbuf.put('"');

    // Adapter OutputRange to escape certain characters
    struct EscString
    {
        void put(uchar c)
        {
            switch (c)
            {
                case '"':
                case '?':
                case '\\':
                    outbuf.put('\\');
                default:
                    outbuf.put(c);
                    break;

                case ESC.expand:
                case ESC.brk:
                    break;               // ignore
            }
        }
    }
    EscString es;

    while (text.length)
    {
        auto c = text[0];
        text = text[1 .. $];
        switch (c)
        {
            case 'R':
                if (text.length && text[0] == '"')
                {
                    outbuf.put('R');
                    es.put('"');
                    text = text[1 .. $].skipRawStringLiteral(es);
                }
                else
                    goto default;
                break;

            case '"':
                es.put(c);
                text = text.skipStringLiteral(es);
                break;

            case '\'':
                outbuf.put(c);
                text = text.skipCharacterLiteral(es);
                break;

            case '?':
                outbuf.put('\\');
            default:
                outbuf.put(c);
                break;

            case ESC.expand:
            case ESC.brk:
                break;               // ignore
        }
    }

    outbuf.put('"');
    auto buf = outbuf[0 .. outbuf.length];
    auto p = cast(uchar*)malloc(buf.length);
    assert(p);
    memcpy(p, buf.ptr, buf.length);
    return p[0 .. buf.length];
}

unittest
{
    auto s = stringize("  ");
    assert(s == `""`);
    if (s.ptr) free(s.ptr);

    s = stringize(" " ~ ESC.space ~ "" ~ ESC.brk ~ "a" ~ ESC.expand ~ "" ~ ESC.brk ~ "bc" ~ ESC.space ~ "" ~ ESC.brk ~ " ");
    assert(s == `"abc"`);
    free(s.ptr);

    s = stringize(`ab?\\x'y'"z"`);
    assert(s == `"ab\?\\x'y'\"z\""`);
    free(s.ptr);

    s = stringize(`'\'a\\'b\`);
    assert(s == `"'\\'a\\\\'b\"`);
    free(s.ptr);

    s = stringize(`"R"x(aa)x""`);
    assert(s == `"\"R\"x(aa)x\"\""`);
    free(s.ptr);

    ubyte[] u = cast(ubyte[])"R\"x(a?\\a)x\"";
    s = stringize(cast(ustring)u);
//writefln("'%s', %s", s, s.length);
    assert(s == `"R\"x(a\?\\a)x\""`);
    free(s.ptr);
}


/********************************************
 * Get Ith arg from args.
 */

private ustring null_arg = cast(ustring)"";

ustring getIthArg(ustring[] args, size_t argi)
{
    if (args.length < argi)
        return null;
    ustring a = args[argi - 1];
    if (a == null)
        a = null_arg; // so we can distinguish a missing arg (null_arg) from an empty arg ("")
    return a;
}

/*******************************************
 * Build macro expanded text.
 * Returns:
 *      malloc'd ustring
 */

uchar[] macroExpandedText(Id* m, ustring[] args)
{
    version (none)
    {
        writefln("macro_replacement_text(m = '%s')", m.name);
        //writefln("\ttext = '%s'", m.text);
        write("\ttext = "); macrotext_print(m.text); writeln();
        for (size_t i = 1; i <= args.length; ++i)
        {
            auto a = getIthArg(args, i);
            writefln("\t[%d] = '%s'", i, a);
        }
    }

    uchar[128] tmpbuf = void;
    auto buffer = Textbuf!uchar(tmpbuf);

    /* Determine if we should elide commas ( ,##__VA_ARGS__ extension)
     */
    size_t va_args = 0;
    if (m.flags & Id.IDdotdotdot)
    {   const margs = m.parameters.length;
        /* Only elide commas if there are more arguments than ...
         * This is unlike GCC, which also elides comments if there is only a ...
         * parameter, unless Standard compliant switches are thrown.
         */
        if (margs >= 2)
        {
            // Only elide commas if __VA_ARGS__ was missing (not blank)
            if (getIthArg(args, margs) is null_arg)
                va_args = margs;
        }
    }

    /* ESC.start, ESC.stringize and ESC.concat only appear in text[]
     */

    for (size_t q = 0; q < m.text.length; ++q)
    {
        if (m.text[q] == ESC.start)
        {
            bool expand = true;
            bool trimleft = false;
            bool trimright = false;

        Lagain2:
            auto argi = m.text[++q];
            switch (argi)
            {
                case ESC.start:           // ESC.start was 'quoted'
                    buffer.put(ESC.start);
                    continue;

                case ESC.stringize:           // stringize argument
                {
                    const argi2 = m.text[++q];
                    const arg = getIthArg(args, argi2);
                    auto a = stringize(arg);
                    buffer.put(a);
                    if (a.ptr) free(a.ptr);
                    continue;
                }

                case ESC.concat:
                    if (m.text[q + 1] == ESC.start)
                    {
                        /* Look for special case of:
                         * ',' ESC.start ESC.concat ESC.start __VA_ARGS__
                         */
                        if (m.text[q + 2] == va_args && q >= 2 && m.text[q - 2] == ',')
                        {
                            /* Elide the comma that was already in buffer,
                             * replace it with ESC.brk
                             */
                             buffer.pop();
                             buffer.put(ESC.brk);
                        }
                        expand = false;
                        trimleft = true;
                        ++q;
                        goto Lagain2;
                    }
                    continue;           // ignore

                default:
                    // If followed by CAT, don't expand
                    if (m.text[q + 1] == ESC.start && m.text[q + 2] == ESC.concat)
                    {   expand = false;
                        trimright = true;

                        /* Special case of ESC.start i ESC.start ESC.concat ESC.start j
                         * Paul Mensonides writes:
                         * In summary, blue paint (PRE_EXP) on either operand of
                         * ## should be discarded unless the concatenation doesn't
                         * produce a new identifier--which can only happen (in
                         * well-defined code) via the concatenation of a
                         * placemarker.  (Concatenation that doesn't produce a
                         * single preprocessing token produces undefined
                         * behavior.)
                         */
                        size_t argj;
                        if (m.text[q + 3] == ESC.start &&
                            (argj = m.text[q + 4]) != ESC.start &&
                            argj != ESC.stringize &&
                            argj != ESC.concat)
                        {
                            //printf("\tspecial CAT case\n");
                            auto a = getIthArg(args, argi);

                            while (a.length && (a[a.length - 1] == ' ' || a[a.length - 1] == ESC.space))
                                a = a[0 .. $ - 1];

                            auto b = getIthArg(args, argj);
                            auto bstart = b;

                            while (b.length && (b[0] == ' ' || b[0] == ESC.space || b[0] == ESC.expand))
                                b = b[1 .. $];

                            if (!(b.length && isIdentifierChar(b[0])))
                                break;
                            if (!a.length && b.length > bstart.length && b.ptr[-1] == ESC.expand)
                             {  // Keep the ESC.expand
                                buffer.put(ESC.expand);
                                buffer.put(b);
                                q += 4;
                                continue;
                             }

                            size_t pe = a.length;
                            while (1)
                            {
                                if (!pe)
                                    goto L1;
                                --pe;
                                if (a[pe] == ESC.expand)
                                    break;
                            }
                            if (!isIdentifierStart(a[pe + 1]))
                                break;

                            for (size_t k = pe + 1; k < a.length; k++)
                            {
                                if (!isIdentifierChar(a[k]))
                                    goto L1;
                            }

                            buffer.put(a[0 .. pe]);
                            buffer.put(a[pe + 1 .. a.length - (pe + 1)]);
                            buffer.put(b);
                            q += 4;
                            continue;
                        }
                    }
                    break;
            }
        L1:
            auto a = getIthArg(args, argi);
            //writefln("\targ[%s] = '%s'", argi, a);
            if (expand)
            {
                auto s = macro_expand(a);
                auto t = trimEscWhiteSpace(s);
                buffer.put(t);
                if (s.ptr) free(cast(void*)s.ptr);
            }
            else
            {
                if (trimleft)
                {
                    while (a.length && (a[0] == ' ' || a[0] == ESC.space || a[0] == ESC.expand))
                        a = a[1 .. $];
                }
                if (trimright)
                {
                    while (a.length && (a[a.length - 1] == ' ' || a[a.length - 1] == ESC.space))
                        a = a[0 .. $ - 1];
                }
                buffer.put(a);
            }
        }
        else
            buffer.put(m.text[q]);
    }

    foreach (arg; args)
        if (arg.ptr) free(cast(void*)arg.ptr);

    auto len = buffer.length;
    auto s = cast(uchar *)malloc(len);
    assert(s);
    memcpy(s, buffer[0 .. len].ptr, len);
    //writefln("\treplacement text = '%s'", s[0 .. len]);
    return s[0 .. len];
}


/*****************************************
 * Return copied string which is a fully macro expanded text.
 * Returns:
 *      ustring that must be free'd
 */

uchar[] macro_expand(ustring text)
{
    return text.dup;
}


/********************************************
 * Read in actual arguments for function-like macro instantiation.
 * Input:
 *      r               input range, sitting just past opening (
 *      nparameters     number of parameters expected
 *      variadic        last parameter is variadic
 * Output:
 *      args    array of actual arguments
 * Returns:
 *      r past closing )
 */

R macroScanArguments(R)(R r, size_t nparameters, bool variadic, out ustring[] args)
{
    bool va_args = variadic && (args.length + 1 == nparameters);
    while (1)
    {
        ustring arg;
        r = r.macroScanArgument(va_args, arg);
        args ~= arg;

        va_args = variadic && (args.length + 1 == nparameters);

        if (r.empty)
        {
            if (va_args)
                args ~= null;
            return r;
        }

        auto c = r.front;
        if (c == ',')
        {
            r.popFront();
        }
        else
        {
            assert(c == ')');           // end of argument list

            if (va_args)
                args ~= null;

            if (args.length != nparameters)
                err_fatal("expected %d macro arguments, had %d", nparameters, args.length);
            r.popFront();
            return r;
        }
    }
    err_fatal("argument list doesn't end with ')'");
    return r;
}

unittest
{
    ustring s;
    ustring[] args;
    s = "ab,cd )a";
    auto r = s.macroScanArguments(2, false, args);
//writefln("'%s', %s", args, args.length);
    assert(!r.empty && r.front == 'a');
    assert(args == ["ab","cd"]);

    s = "ab )a";
    r = s.macroScanArguments(2, true, args);
//writefln("'%s', %s", args, args.length);
    assert(!r.empty && r.front == 'a');
    assert(args == ["ab",""]);
}

/*****************************************
 * Read in macro actual argument.
 * Input:
 *      r       input range at start of arg
 *      va_args if scanning argument for __VA_ARGS__
 * Output:
 *      arg     malloc'd copy of the scanned argument
 * Returns:
 *      range set past end of argument
 */

R macroScanArgument(R)(R r, bool va_args, out ustring arg)
{
    int parens;

    uchar[1000] tmpbuf = void;
    auto outbuf = Textbuf!uchar(tmpbuf);
    outbuf.put(0);

    while (1)
    {
        if (r.empty)
            break;
        auto c = r.front;
        switch (c)
        {
            case '(':
                parens++;
                break;

            case ')':
                if (outbuf.last() == ' ')
                    outbuf.pop();
                if (!parens)
                    goto LendOfArg;
                --parens;
                break;

            case ',':
                if (!parens && !va_args)
                    goto LendOfArg;
                break;

            case ' ':
            case '\t':
            case '\r':
            case '\n':
            case '\v':
            case '\f':
                // Collapse all whitespace into a single ' '
                if (outbuf.last() != ' ')
                    outbuf.put(' ');
                r.popFront();
                continue;

            case '"':
                r.popFront();
                if (outbuf.last() == 'R')
                {
                    outbuf.put(cast(uchar)c);
                    r = r.skipRawStringLiteral(outbuf);
                }
                else
                {
                    outbuf.put(cast(uchar)c);
                    r = r.skipStringLiteral(outbuf);
                }
                continue;

            case '\'':
                outbuf.put(cast(uchar)c);
                r.popFront();
                r = r.skipCharacterLiteral(outbuf);
                continue;

            case '/':
            case '*':
                if (outbuf.last() == '/')
                {
                    if (c == '/')
                        r = r.skipCppComment();
                    else
                        r = r.skipCComment();
                    outbuf.pop();               // elide comment from preprocessed output
                    goto case ' ';
                }
                break;

            default:
                break;
        }
        outbuf.put(cast(uchar)c);
        r.popFront();
    }
    err_fatal("premature end of macro argument");
    return r;

  LendOfArg:
    auto len = outbuf.length - 1;
    auto s = cast(uchar *)malloc(len);
    assert(s);
    memcpy(s, outbuf[1 .. len + 1].ptr, len);
    //writefln("\targ = '%s'", s[0 .. len]);
    arg = cast(ustring)s[0 .. len];
    return r;
}

unittest
{
    ustring s = " \t\r\n\v\f /**/ //
 )a";
    ustring arg;
    auto r = s.macroScanArgument(false, arg);
    assert(!r.empty && r.front == ')');
    assert(arg == "");

    s = " ((,)) )a";
    r = s.macroScanArgument(false, arg);
    assert(!r.empty && r.front == ')');
    assert(arg == " ((,))");

    s = "ab,cd )a";
    r = s.macroScanArgument(false, arg);
    assert(!r.empty && r.front == ',');
    assert(arg == "ab");

    s = "ab,cd )a";
    r = s.macroScanArgument(true, arg);
    assert(!r.empty && r.front == ')');
    assert(arg == "ab,cd");

    s = "a'b',cd )a";
    r = s.macroScanArgument(false, arg);
    assert(!r.empty && r.front == ',');
    assert(arg == "a'b'");

    s = `a"b",cd )a`;
    r = s.macroScanArgument(false, arg);
    assert(!r.empty && r.front == ',');
    assert(arg == `a"b"`);

    s = `aR"x(b")x",cd )a`;
    r = s.macroScanArgument(false, arg);
//writefln("|%s|, %s", arg, arg.length);
    assert(!r.empty && r.front == ',');
    assert(arg == `aR"x(b")x"`);
}
