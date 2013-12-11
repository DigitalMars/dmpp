
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module directive;

import std.algorithm;
import std.stdio;

import id;
import lexer;
import macros;
import main;
import sources;

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
                    err_fatal("multiple parameter '%s'", id);
                params ~= id.idup;
                r.popFront();
                switch (r.front)
                {
                    case TOK.comma:
                        r.popFront();
                        continue;

                    case TOK.dotdotdot:
                    case TOK.rparen:
                        continue;

                    default:
                        err_fatal("')' expected");
                        return;
                }

            case TOK.dotdotdot:
                variadic = true;
                params ~= cast(ustring)"__VA_ARGS__";
                r.popFront();
                if (r.front != TOK.rparen)
                {
                    err_fatal("')' expected");
                    return;
                }
                break;

            default:
                err_fatal("identifier expected");
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
        text = macroReplacementList(objectLike, parameters, text ~ '\n');
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
 */

void parseDirective(R)(ref R r)
{
    r.popFront();
    if (r.empty)
    {
        return;
    }

    bool linemarker = void;
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
                        auto sf = r.src.currentSourceFile();
                        if (sf)
                            sf.loc.srcFile.once = true;

                        // Turn off expanded output so this line is not emitted
                        r.src.expanded.off();
                        r.src.expanded.lineBuffer.initialize();
                        while (1)
                        {
                            r.popFront();
                            if (r.empty)
                            {   r.src.expanded.on();
                                goto Ldefault;
                            }
                            if (r.front == TOK.eol)
                                break;
                        }
                        r.src.expanded.on();
                        r.src.expanded.put(r.src.front);
                        return;
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
                    return;

                case "define":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFront();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal("identifier expected following #define");
                        return;
                    }

                    auto macid = r.idbuf[].idup;

                    ustring[] parameters;
                    bool objectLike = true;
                    bool variadic;

                    if (r.src.front == '(')
                    {
                        r.popFront();
                        assert(r.front == TOK.lparen);
                        r.popFront();
                        objectLike = false;
                        r.lexMacroParameters(variadic, parameters);
                    }
                    auto definition = r.src.restOfLine();
                    auto text = macroReplacementList(objectLike, parameters, definition);

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
                    return;
                }

                case "undef":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFront();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal("identifier expected following #define");
                        return;
                    }

                    auto m = Id.search(r.idbuf[]);
                    if (m)
                        m.flags &= ~Id.IDmacro;

                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal("end of line expected");

                    r.src.expanded.on();
                    return;
                }

                case "error":
                    auto msg = r.src.restOfLine();
                    err_fatal("%s", msg);
                    return;

                case "ifdef":
                {
                    // Turn off expanded output so this line is not emitted
                    r.src.expanded.off();
                    r.src.expanded.lineBuffer.initialize();

                    r.popFront();
                    assert(!r.empty);
                    if (r.front != TOK.identifier)
                    {   r.src.expanded.on();
                        err_fatal("identifier expected following #ifdef");
                        return;
                    }

                    auto m = Id.search(r.idbuf[]);
                    auto cond = (m && m.flags & Id.IDmacro);

                    r.popFront();
                    if (r.front != TOK.eol)
                        err_fatal("end of line expected");

                    r.src.expanded.on();
                    return;
                }

                case "ifndef":
                case "if":
                case "else":
                case "elif":
                case "endif":
                case "include":
                    assert(0);

                default:
                    err_fatal("unrecognized preprocessing directive #%s", id);
                    r.popFront();
                    return;
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
                return;
            sf.loc.lineNumber = cast(uint)(r.number.value - 1);
            r.needStringLiteral();
            r.popFront();
            if (r.empty || r.front == TOK.eol)
                break;
            while (!r.empty && r.front == TOK.string)
            {
                r.popFront();
            }
            // The string is in r.idbuf[]
            auto s = cast(string)r.getStringLiteral();

            // s is the new "source file"
            auto srcfile = SrcFile.lookup(s.idup);
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
                err_fatal("end of line expected");
            }
            break;
        }

        case TOK.eol:
            r.popFront();
            break;

        case TOK.eof:
        Leof:
            assert(0);          // lines should always end with TOK.eol

        default:
        Ldefault:
            err_fatal("preprocessing directive expected");
            r.popFront();
            break;
    }
}
