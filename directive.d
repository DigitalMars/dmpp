
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module directive;

import std.algorithm;
import std.stdio;
import std.string;

import constexpr;
import id;
import lexer;
import macros;
import main;
import skip;
import sources;
import stringlit;
import textbuf;

enum : ubyte
{
    CONDguard,          // a possible #include guard
    CONDendif,          // looking for #endif only
    CONDif,             // looking for #else, #elif, or #endif
    CONDtoendif,        // skipping over #else, #elif, looking for #endif
}

/*******************************
 * Parse the macro parameter list.
 * Input:
 *      r       on the character following the '('
 * Output:
 *      variadic        true if variadic parameter list
 *      parameters      the parameters
 * Returns:
 *      r               on character following the ')'
 */

void lexMacroParameters(R)(ref R r, out bool variadic, out ustring[] parameters)
{
    ustring[] params;

    while (1)
    {
        switch (r.front)
        {
            case TOK.rparen:
                parameters = params;
                return;

            case TOK.identifier:
                auto id = cast(ustring)r.idbuf[];
                if (params.countUntil(id) >= 0)
                    err_fatal(r.loc(), "multiple macro parameters named '%s'", id);
                params ~= id.idup;
                r.popFrontNoExpand();
                switch (r.front)
                {
                    case TOK.comma:
                        r.popFrontNoExpand();
                        continue;

                    case TOK.dotdotdot:
                    case TOK.rparen:
                        continue;

                    default:
                        err_fatal(r.loc(), "')' expected to close macro parameter list");
                        return;
                }

            case TOK.dotdotdot:
                variadic = true;
                params ~= cast(ustring)"__VA_ARGS__";
                r.popFrontNoExpand();
                if (r.front != TOK.rparen)
                {
                    err_fatal("')' expected");
                    return;
                }
                break;

            default:
                err_fatal(r.loc(), "identifier expected for macro parameter");
                return;
        }
    }
}


/**************************************************
 * Define macro of the form:
 *      name
 *      name=definition
 *      name(parameters)=definition
 * which comes from the -D command line switch.
 *
 * Input:
 *      def     macro
 */

void macrosDefine(ustring def)
{
    ustring id;
    ustring[] parameters;
    ustring text;
    bool objectLike = true;
    bool variadic;

    auto lexer = createLexer(def);
    if (lexer.empty)
        goto Lerror;
    if (lexer.front != TOK.identifier)
        goto Lerror;

    id = lexer.idbuf[].idup;
    lexer.popFront();

    if (lexer.empty)
        text = cast(ustring)"1";
    else
    {
        auto c = lexer.front;
        switch (c)
        {
            case TOK.lparen:
                lexer.popFront();
                objectLike = false;
                lexer.lexMacroParameters(variadic, parameters);
                lexer.popFront();
                if (!lexer.empty && lexer.front != TOK.eof && lexer.front != TOK.eol)
                {
                    if (lexer.front != TOK.assign)
                    {
                        err_fatal("'=' expected after macro parameter list");
                        return;
                    }
                    text = lexer.src[];
                }
                break;

            case TOK.assign:
                text = lexer.src[];
                break;

            case TOK.eol:
            case TOK.eof:
                text = cast(ustring)"1";
                break;

            default:
                goto Lerror;
        }
        text ~= '\n';
        text = macroReplacementList(objectLike, parameters, text);
    }

    uint flags = Id.IDpredefined;
    if (variadic)
        flags |= Id.IDdotdotdot;
    if (!objectLike)
        flags |= Id.IDfunctionLike;

    auto m = Id.defineMacro(id, parameters, text, flags);
    if (!m)
    {
        err_fatal("redefinition of macro %s", id);
    }
    return;

Lerror:
    err_fatal("malformed macro definition");
}

unittest
{
  {
    auto d = cast(ustring)"hello";
    macrosDefine(d);
    auto m = Id.search(d);
    assert(m && m.name == d && m.flags == (Id.IDmacro | Id.IDpredefined) && m.text == "1");
  }
  {
    auto n = cast(ustring)"betty";
    auto d = n ~ cast(ustring)"=value";
    macrosDefine(d);
    auto m = Id.search(n);
    assert(m && m.name == n && m.flags == (Id.IDmacro | Id.IDpredefined) && m.text == "value");
  }
  {
    auto n = cast(ustring)"betty2";
    auto d = n ~ cast(ustring)"()";
    macrosDefine(d);
    auto m = Id.search(n);
    assert(m && m.name == n && m.flags == (Id.IDmacro | Id.IDpredefined | Id.IDfunctionLike) && m.text == "");
  }
  {
    auto n = cast(ustring)"betty3";
    auto d = n ~ cast(ustring)"/**/(...) =value ";
    macrosDefine(d);
    auto m = Id.search(n);
    assert(m && m.name == n && m.flags == (Id.IDmacro | Id.IDpredefined | Id.IDfunctionLike | Id.IDdotdotdot) && m.text == "value");
  }
  {
    auto n = cast(ustring)"betty4";
    auto d = n ~ cast(ustring)"/**/(a,...) =value ";
    macrosDefine(d);
    auto m = Id.search(n);
    assert(m && m.name == n && m.flags == (Id.IDmacro | Id.IDpredefined | Id.IDfunctionLike | Id.IDdotdotdot) && m.text == "value");
    assert(m.parameters == ["a", "__VA_ARGS__"]);
  }
  {
    auto n = cast(ustring)"betty5";
    auto d = n ~ cast(ustring)" (a ...) =value ";
    macrosDefine(d);
    auto m = Id.search(n);
//writefln("text = '%s'", m.text);
    assert(m && m.name == n && m.flags == (Id.IDmacro | Id.IDpredefined | Id.IDfunctionLike | Id.IDdotdotdot) && m.text == "value");
//writeln(m.parameters);
    assert(m.parameters == ["a", "__VA_ARGS__"]);
  }
}


/*********************************************
 * Seen a '#', the start of a preprocessing directive.
 * Lexer has just finished the #, has not read next token yet.
 * Input:
 *      r       the lexer
 * Ouput:
 *      r       start of next line
 * Returns:
 *      true    if this preprocessor directive counts as a token
 */

bool parseDirective(R)(ref R r)
{
    r.popFrontNoExpand();
    if (r.empty)
    {
        return false;
    }

    bool cond = void;
    bool linemarker = void;
    bool includeNext;

    switch (r.front)
    {
        case TOK.identifier:
        {
            auto id = r.idbuf[];
            switch (id)
            {
                case "line":
                    // #line directive
                    linemarker = false;
                    r.popFront();
                    if (r.empty)
                        goto Leof;
                    if (r.front == TOK.integer)
                        goto Lline;
                    goto Ldefault;

                case "pragma":
                    r.popFront();
                    assert(!r.empty);
                    if (r.front == TOK.identifier && r.idbuf[] == "once")
                    {
                        auto csf = r.src.currentSourceFile();
                        if (csf)
                            csf.loc.srcFile.once = true;

                        // Turn off expanded output so this line is not emitted
                        r.src.expanded.off();
                        r.src.expanded.lineBuffer.initialize();

                        r.popFront();
                        if (r.front != TOK.eol)
                            err_fatal(r.loc(), "end of line expected following #pragma once");
                        r.src.expanded.on();
                        r.src.expanded.put('\n');
                        r.src.expanded.put(r.src.front);
                        return true;
                    }
                    /* Ignore the directive
                     */
                    while (1)
                    {
                        r.popFront();
                        if (r.empty)
                            goto Ldefault;
                        if (r.front == TOK.eol)
                            break;
                    }
                    return true;

                case "define":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFrontNoExpand();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal(r.loc(), "identifier expected following #define");
                        return true;
                    }

                    auto macid = r.idbuf[].idup;

                    ustring[] parameters;
                    bool objectLike = true;
                    bool variadic;

                    if (r.src.front == '(')
                    {
                        r.popFrontNoExpand();
                        assert(r.front == TOK.lparen);
                        r.popFrontNoExpand();
                        objectLike = false;
                        r.lexMacroParameters(variadic, parameters);
                    }

                    auto text = macroReplacementList(objectLike, parameters, r.src);

                    uint flags = 0;
                    if (variadic)
                        flags |= Id.IDdotdotdot;
                    if (!objectLike)
                        flags |= Id.IDfunctionLike;

                    auto m = Id.defineMacro(macid, parameters, text, flags);
                    if (!m)
                    {
                        err_fatal("redefinition of macro %s", id);
                    }
                    r.src.expanded.on();
                    r.front = TOK.eol;
                    return true;
                }

                case "undef":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFrontNoExpand();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal(r.loc(), "identifier expected following #undef");
                        return true;
                    }

                    auto m = Id.search(r.idbuf[]);
                    if (m)
                        m.flags &= ~Id.IDmacro;

                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal(r.loc(), "end of line expected following #undef");

                    r.src.expanded.on();
                    return true;
                }

                case "error":
                    auto msg = r.src.restOfLine();
                    err_fatal("%s", msg);
                    return true;

                case "if":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFront();
                    assert(!r.empty);

                    cond = r.constantExpression();

                    r.src.ifstack.put(CONDif);

                    if (r.front != TOK.eol)
                        err_fatal(r.loc(), "end of line expected after #if expression");

                    if (!cond)
                    {
                        r.skipFalseCond();
                        return true;
                    }

                    r.src.expanded.on();
                    return true;
                }

                case "ifdef":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFrontNoExpand();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal(r.loc(), "identifier expected following #ifdef");
                        return true;
                    }

                    auto m = Id.search(r.idbuf[]);
                    cond = (m && m.flags & Id.IDmacro);

                    r.src.ifstack.put(CONDif);
                Ldef:
                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal(r.loc(), "end of line expected following identifier");

                    if (!cond)
                    {
                        r.skipFalseCond();
                        return true;
                    }

                    r.src.expanded.on();
                    return true;
                }

                case "ifndef":
                {
                    bool seenTokens = false;
                    auto sf = r.src.currentSourceFile();
                    if (sf)
                        seenTokens = sf.seenTokens;

                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFrontNoExpand();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal(r.loc(), "identifier expected following #ifndef");
                        return true;
                    }

                    auto m = Id.search(r.idbuf[]);
                    cond = !(m && m.flags & Id.IDmacro);

                    auto cnd = CONDif;
                    if (cond && sf && !seenTokens && sf.includeGuard == null)
                    {
                        sf.includeGuard = r.idbuf[].dup;
                        sf.ifstacki = r.src.ifstack.length();
                        cnd = CONDguard;
                    }

                    r.src.ifstack.put(cnd);
                    goto Ldef;
                }

                case "else":
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();
                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal("5end of line expected");
                    if (r.src.ifstack.length == 0 || r.src.ifstack.last() == CONDendif)
                        err_fatal("#else by itself");
                    else
                    {
                        r.src.ifstack.pop();
                        r.src.ifstack.put(CONDendif);
                        r.skipFalseCond();
                    }
                    return true;

                case "elif":
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();
                    while (!r.empty)
                    {
                        r.popFront();
                        if (r.front == TOK.eol)
                            break;
                        assert(r.front != TOK.eof);
                    }
                    if (r.src.ifstack.length == 0 || r.src.ifstack.last() == CONDendif)
                        err_fatal(r.loc(), "#elif by itself");
                    else
                    {
                        r.src.ifstack.pop();
                        r.src.ifstack.put(CONDtoendif);
                        r.skipFalseCond();
                    }
                    return true;

                case "endif":
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();
                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal("6end of line expected");
                    r.src.expanded.on();
                    r.src.expanded.put('\n');
                    r.src.expanded.put(r.src.front);
                    if (r.src.ifstack.length == 0)
                        err_fatal("#endif by itself");
                    else
                    {
                        if (r.src.ifstack.last() == CONDguard)
                        {
                            auto sf = r.src.currentSourceFile();
                            if (sf &&
                                sf.includeGuard != null &&
                                sf.ifstacki == r.src.ifstack.length() - 1)
                            {
                                sf.seenTokens = false;
                                r.src.ifstack.pop();
                                return false;
                            }
                        }
                        r.src.ifstack.pop();
                    }
                    return true;

                case "include_next":
                    includeNext = true;
                    goto Linclude;

                case "include":
                Linclude:
                {
                    auto sf = r.src.currentSourceFile();
                    if (sf)
                        sf.seenTokens = true;

                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    uchar[30] tmpbuf = void;
                    auto stringbuf = Textbuf!uchar(tmpbuf);
                    const(uchar)[] s;
                    bool sysstring = false;

                    r.src.skipWhitespace();
                    if (r.src.front == '"')
                    {
                        r.src.popFront();
                        r.src.lexStringLiteral(stringbuf, '"', STR.f);
                        s = stringbuf[];
                        r.popFront();
                    }
                    else if (r.src.front == '<')
                    {
                        sysstring = true;
                        r.src.popFront();
                        s = stringbuf[];
                        r.src.lexStringLiteral(stringbuf, '>', STR.f);
                        r.popFront();
                    }
                    else
                    {
                        r.needStringLiteral();
                        r.popFront();
                        if (r.front == TOK.string)
                        {
                        }
                        else if (r.front == TOK.sysstring)
                            sysstring = true;
                        else
                            err_fatal(r.loc(), "string expected");
                        s = r.getStringLiteral();
                        r.popFront();
                    }
                    if (s.length == 0)
                        err_fatal(r.loc(), "filename expected");
                    if (r.front != TOK.eol)
                        err_fatal(r.loc(), "end of line expected following #include");
                    r.src.unget();
                    r.src.push('\n');
                    r.src.includeFile(includeNext, sysstring, s.idup);
                    r.src.popFront();
                    r.src.expanded.on();
                    r.popFront();
                    return false;
                }

                default:
                    err_fatal(r.loc(), "unrecognized preprocessing directive #%s", id);
                    r.popFront();
                    return true;
            }
            break;
        }

        case TOK.integer:
            // So-called "linemarker" record
            linemarker = true;
        Lline:
        {
            auto sf = r.src.currentSourceFile();
            if (!sf)
                return true;
            sf.loc.lineNumber = cast(uint)(r.number.value - 1);

            char[32] tmpbuf = void;
            auto stringbuf = Textbuf!char(tmpbuf);
            stringbuf.initialize();

            r.needStringLiteral();
            r.popFront();
            if (r.empty || r.front == TOK.eol)
                break;
            while (!r.empty && r.front == TOK.string)
            {
                auto s = cast(string)r.getStringLiteral();
                stringbuf.put(s);       // append to stringbuf[]
                r.popFront();
            }

            // s is the new "source file"
            auto srcfile = SrcFile.lookup(stringbuf[].idup);
            stringbuf.free();
            srcfile.contents = sf.loc.srcFile.contents;
            srcfile.includeGuard = sf.loc.srcFile.includeGuard;
            srcfile.once = sf.loc.srcFile.once;

            sf.loc.srcFile = srcfile;

            if (linemarker)
            {
                while (!r.empty && r.front == TOK.integer)
                {
                    r.popFront();
                }
            }
            if (r.empty || r.front != TOK.eol)
            {
                err_fatal(r.loc(), "end of line expected after linemarker");
            }
            break;
        }

        case TOK.eol:
            r.popFront();
            return false;

        case TOK.eof:
        Leof:
            assert(0);          // lines should always end with TOK.eol

        default:
        Ldefault:
            err_fatal(r.loc(), "preprocessing directive expected");
            r.popFront();
            break;
    }
    return true;
}

/***************************************
 * Consume input until a #else, #elif, or #endif is seen.
 * Input:
 *      lexer   at beginning of line
 */

void skipFalseCond(R)(ref R r)
{
    auto starti = r.src.ifstack.length;

    r.popFront();
    while (!r.empty)
    {
        assert(!r.empty);
        if (r.front == TOK.hash)
        {
            // Start of preprocessing directive
            r.popFront();
            if (r.front == TOK.identifier)
            {
                auto id = r.idbuf[];
                switch (id)
                {
                    case "if":
                    case "ifdef":
                    case "ifndef":
                        r.src.ifstack.put(CONDif);
                        break;

                    case "elif":
                        final switch (r.src.ifstack.last())
                        {
                            case CONDendif:
                                err_fatal("#elif not following #if");
                                break;

                            case CONDif:
                            case CONDguard:
                                if (starti == r.src.ifstack.length())
                                {
                                    // Same code here as for #if
                                    r.popFront();
                                    auto cond = r.constantExpression();

                                    r.src.ifstack.pop();
                                    r.src.ifstack.put(CONDif);

                                    if (r.front != TOK.eol)
                                        err_fatal(r.loc, "end of line expected following #elif expr");

                                    if (cond)
                                    {
                                        r.src.expanded.on();
                                        r.src.expanded.put(r.src.front);
                                        return;
                                    }
                                }
                                break;

                            case CONDtoendif:
                                break;
                        }
                        break;

                    case "else":
                        final switch (r.src.ifstack.last())
                        {
                            case CONDendif:
                                err_fatal("#else not following #if");
                                break;

                            case CONDif:
                            case CONDguard:
                                if (starti == r.src.ifstack.length())
                                {
                                    // Skip the rest of the line
                                    r.src.restOfLine();
                                    r.popFront();
                                    r.src.expanded.on();
                                    return;
                                }
                                break;

                            case CONDtoendif:
                                break;
                        }
                        break;

                    case "endif":
                        if (starti == r.src.ifstack.length())
                        {
                            r.src.ifstack.pop();

                            // Skip the rest of the line
                            r.src.restOfLine();
                            r.src.expanded.on();
                            r.popFront();
                            return;
                        }
                        r.src.ifstack.pop();
                        break;

                    default:
                        break;
                }
            }
        }

        if (r.front == TOK.eol)
        {
            r.popFront();
        }
        else
        {
            // Skip the rest of the line
            r.src.restOfLine();
            r.popFront();
        }
    }
    err_fatal("end of file found before #endif");
}

/*************************************
 * Process #include file
 * Input:
 *      includeNext     if it was #include_next
 *      system          if <file>
 *      s               the filename string
 */

void includeFile(R)(R ctx, bool includeNext, bool sysstring, const(char)[] s)
{
    s = strip(s);       // remove leading and trailing whitespace

    auto csf = ctx.currentSourceFile();
    if (csf && csf.loc.isSystem)
        sysstring = true;

    auto sf = ctx.searchForFile(includeNext, sysstring, s);
    if (!sf)
    {
        err_fatal("#include file '%s' not found", s);
        return;
    }

    // Check for #pragma once
    if (sf.once)
    {
        if (ctx.params.verbose)
            writefln("skipping '%s'", sf.filename);
        return;
    }

    // Check for #include guard
    if (sf.includeGuard.length)
    {
        auto m = Id.search(sf.includeGuard);
        if (m && m.flags & Id.IDmacro)
        {
            if (ctx.params.verbose)
                writefln("skipping '%s'", sf.filename);
            return;
        }
    }

    ctx.pushFile(sf, sysstring);
}

