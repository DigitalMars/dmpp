
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

/*******************************
 * Parse the macro parameter list.
 * Input:
 *      r       on the character following the '('
 * Output:
 *      variadic        true if variadic parameter list
 *      parameters      the parameters
 * Returns:
 *      r               following the ')'
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
                r.popFront();
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

