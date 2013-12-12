
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module lexer;

import std.array;
import std.ascii;
import std.range;
import std.stdio;
import std.traits;

import id;
import macros;
import main;
import number;
import ranges;
import skip;
import stringlit;

/**
 * Only a relatively small number of tokens are of interest to the preprocessor.
 */

enum TOK
{
    reserved,

    other,     // not of interest to the preprocessor
    eol,       // end of line
    eof,       // end of file

    comma,
    question,
    colon,
    oror,
    andand,
    or,
    and,
    xor,
    plus,
    minus,
    equal,
    notequal,
    lt,
    gt,
    le,
    ge,
    shl,
    shr,
    mul,
    div,
    mod,
    not,
    tilde,
    lparen,
    rparen,
    defined,
    dotdotdot,
    assign,
    hash,

    integer,
    identifier,
    string,
    sysstring,
}

alias long ppint_t;
alias ulong ppuint_t;

struct PPnumber
{
    ppint_t value;
    bool isunsigned;    // if value is an unsigned integer
}

struct Lexer(R) if (isInputRange!R)
{
    TOK front;
    PPnumber number;

    R src;

    alias Unqual!(ElementEncodingType!R) E;
    BitBucket!E bitbucket = void;
    EmptyInputRange!E emptyrange = void;

    //enum bool isContext = std.traits.hasMember!(R, "expanded");
    enum bool isContext = __traits(compiles, src.expanded);

    StaticArrayBuffer!(E, 1024) idbuf = void;

    bool stringLiteral;

    void needStringLiteral()
    {
        idbuf.init();           // put the string literal in idbuf[]
        stringLiteral = true;
    }

    E[] getStringLiteral()
    {
        stringLiteral = false;
        return idbuf[];
    }

    enum empty = false;         // return TOK.eof for going off the end

    void popFront()
    {
        //writefln("isContext %s, %s", isContext, __traits(compiles, src.expanded));

        bool expanded = void;

        while (1)
        {
            if (src.empty)
            {
                front = TOK.eof;
                return;
            }

            E c = cast(E)src.front;
            switch (c)
            {
                case ' ':
                case '\t':
                case '\r':
                case '\v':
                case '\f':
                case ESC.space:
                case ESC.brk:
                    src.popFront();
                    continue;

                case '\n':
                    src.popFront();
                    front = TOK.eol;
                    return;

                case '0': .. case '9':
                {
                    bool isinteger;
                    src = src.lexNumber(number.value, number.isunsigned, isinteger);
                    front = isinteger ? TOK.integer : TOK.other;
                    return;
                }

                case '.':
                    src.popFront();
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '0': .. case '9':
                                src = src.skipFloat(bitbucket, false, true, false);
                                break;

                            case '*':
                                src.popFront();
                                break;

                            case '.':
                                src.popFront();
                                if (!src.empty && src.front == '.')
                                {
                                    src.popFront();
                                    front = TOK.dotdotdot;
                                    return;
                                }
                                break;

                            default:
                                break;
                        }
                    }
                    goto Lother;

                case '!':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.notequal;
                        return;
                    }
                    front = TOK.not;
                    return;

                case '=':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.equal;
                        return;
                    }
                    front = TOK.assign;
                    return;

                case '<':
                    src.popFront();
                    static if (isContext)
                    {
                        if (stringLiteral)
                        {
                            src = src.lexStringLiteral(idbuf, '>', STR.f);
                            front = TOK.sysstring;
                            return;
                        }
                    }
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.le;
                        return;
                    }
                    if (!src.empty && src.front == '<')
                    {
                        src.popFront();
                        front = TOK.shl;
                        return;
                    }
                    front = TOK.lt;
                    return;

                case '>':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.ge;
                        return;
                    }
                    if (!src.empty && src.front == '>')
                    {
                        src.popFront();
                        front = TOK.shr;
                        return;
                    }
                    front = TOK.gt;
                    return;

                case '%':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.mod;
                    return;

                case '*':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.mul;
                    return;

                case '^':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.xor;
                    return;

                case '+':
                    src.popFront();
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    if (!src.empty && src.front == '+')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.plus;
                    return;

                case '-':
                    src.popFront();
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                            case '-':
                                src.popFront();
                                goto Lother;

                            case '>':
                                src.popFront();
                                if (!src.empty && src.front == '*')
                                    src.popFront();
                                goto Lother;

                            default:
                                break;
                        }
                    }
                    front = TOK.minus;
                    return;

                case '&':
                    src.popFront();
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                                src.popFront();
                                goto Lother;

                            case '&':
                                src.popFront();
                                front = TOK.andand;
                                return;

                            default:
                                break;
                        }
                    }
                    front = TOK.and;
                    return;

                case '|':
                    src.popFront();
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                                src.popFront();
                                goto Lother;

                            case '|':
                                src.popFront();
                                front = TOK.oror;
                                return;

                            default:
                                break;
                        }
                    }
                    front = TOK.or;
                    return;

                case '(':    src.popFront(); front = TOK.lparen;    return;
                case ')':    src.popFront(); front = TOK.rparen;    return;
                case ',':    src.popFront(); front = TOK.comma;     return;
                case '?':    src.popFront(); front = TOK.question;  return;
                case ':':    src.popFront(); front = TOK.colon;     return;
                case '~':    src.popFront(); front = TOK.tilde;     return;
                case '#':    src.popFront(); front = TOK.hash;      return;

                case '{':
                case '}':
                case '[':
                case ']':
                case ';':
                    src.popFront();
                    goto Lother;

                case '/':
                    src.popFront();
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                                src.popFront();
                                goto Lother;

                            case '/':
                                src.popFront();
                                src = src.skipCppComment();
                                continue;

                            case '*':
                                src.popFront();
                                src = src.skipCComment();
                                continue;

                            default:
                                break;
                        }
                    }
                    front = TOK.div;
                    return;

                case '"':
                    src.popFront();
                    static if (isContext)
                    {
                        if (stringLiteral)
                        {
                            src = src.lexStringLiteral(idbuf, '"', STR.f);
                            front = TOK.string;
                            return;
                        }
                        else
                            src = src.skipStringLiteral(bitbucket);
                    }
                    else
                    {
                        src = src.skipStringLiteral(bitbucket);
                    }
                    goto Lother;

                case '\'':
                    src.popFront();
                    src = src.lexCharacterLiteral(number.value, STR.s);
                    number.isunsigned = false;
                    front = TOK.integer;
                    return;

                case '$':
                case '_':
                case 'a': .. case 't':
                case 'v': .. case 'z':
                case 'A': .. case 'K':
                case 'M': .. case 'Q':
                case 'S': .. case 'T':
                case 'V': .. case 'Z':
                    static if (isContext)
                    {
                        expanded = src.isExpanded();
                        src.expanded.popBack();
                        src.expanded.off();
                    }
                    idbuf.init();
                    src = src.inIdentifier(idbuf);
                Lident:
                    static if (!isContext)
                    {
                        front = TOK.identifier;
                        return;
                    }
                    else
                    {
                        if (expanded && !src.empty && src.isExpanded())
                            goto Lisident;
                        auto m = Id.search(idbuf[]);
                        if (m && m.flags & Id.IDmacro)
                        {
                            assert(!(m.flags & Id.IDinuse));

                            if (m.flags & (Id.IDlinnum | Id.IDfile | Id.IDcounter))
                            {   // Predefined macro
                                src.unget();
                                auto p = src.predefined(m);
                                src.push(p);
                                src.expanded.on();
                                src.popFront();
                                continue;
                            }
                            ustring[] args;
                            if (m.flags & Id.IDfunctionLike)
                            {
                                /* Scan up to opening '(' of actual argument list
                                 */
                                E space = 0;
                                while (1)
                                {
                                    if (src.empty)
                                    {
                                        if (space)
                                        {
                                            src.expanded.on();
                                            src.expanded.put(idbuf[]);
                                            src.expanded.put(' ');
                                            front = TOK.identifier;
                                            return;
                                        }
                                        goto Lisident;
                                    }
                                    c = cast(E)src.front;
                                    switch (c)
                                    {
                                        case ' ':
                                        case '\t':
                                        case '\r':
                                        case '\n':
                                        case '\v':
                                        case '\f':
                                        case ESC.space:
                                        case ESC.brk:
                                            space = c;
                                            src.popFront();
                                            continue;

                                        case '/':
                                            src.popFront();
                                            if (src.empty)
                                            {   c = 0;
                                                goto default;
                                            }
                                            c = src.front;
                                            if (c == '*')
                                            {
                                                src.popFront();
                                                src = src.skipCComment();
                                                space = ' ';
                                                continue;
                                            }
                                            if (c == '/')
                                            {
                                                src.popFront();
                                                src = src.skipCppComment();
                                                space = ' ';
                                                continue;
                                            }
                                            src.push('/');
                                            goto default;

                                        case '(':           // found start of argument list
                                            src.popFront();
                                            break;

                                        default:
                                            src.expanded.on();
                                            src.expanded.put(idbuf[]);
                                            if (space)
                                                src.expanded.put(space);
                                            if (c)
                                                src.push(c);
                                            front = TOK.identifier;
                                            return;
                                    }
                                    break;
                                }

                                src = src.macroScanArguments(m.parameters.length,
                                        !!(m.flags & Id.IDdotdotdot),
                                         args, emptyrange);
                            }
                            auto xcnext = src.front;

                            if (!src.empty)
                                src.unget();

                            auto p = macroExpandedText!(typeof(*src))(m, args);
                            //writefln("expanded: '%s'", p);
                            auto q = macroRescan!(typeof(*src))(m, p);
                            //writefln("rescanned: '%s'", q);
                            //if (p.ptr) free(p.ptr);

                            /*
                             * Insert break if necessary to prevent
                             * token concatenation.
                             */
                            if (!isWhite(xcnext))
                            {
                                src.push(ESC.brk);
                            }

                            src.push(q);
                            src.setExpanded();
                            src.expanded.on();
                            src.expanded.put(ESC.brk);
                            src.popFront();
                            continue;
                        }

                    Lisident:
                        src.expanded.on();
                        src.expanded.put(idbuf[]);
                        src.expanded.put(src.front);
                        front = TOK.identifier;
                        return;
                    }

                case 'L':
                case 'u':
                case 'U':
                case 'R':
                    // string prefixes: L LR u u8 uR u8R U UR R
                    static if (isContext)
                    {
                        expanded = src.isExpanded();
                        src.expanded.popBack();
                        src.expanded.off();
                    }
                    idbuf.init();
                    src = src.inIdentifier(idbuf);
                    if (!src.empty)
                    {
                        if (src.front == '"')
                        {
                            switch (cast(string)idbuf[])
                            {
                                case "LR":
                                case "R":
                                case "u8R":
                                case "uR":
                                case "UR":
                                    static if (isContext)
                                    {
                                        src.expanded.on();
                                        src.expanded.put(idbuf[]);
                                        src.expanded.put(src.front);
                                    }
                                    src.popFront();
                                    src = src.skipRawStringLiteral(bitbucket);
                                    goto Lother;

                                case "L":
                                case "u":
                                case "u8":
                                case "U":
                                    static if (isContext)
                                    {
                                        src.expanded.on();
                                        src.expanded.put(idbuf[]);
                                        src.expanded.put(src.front);
                                        src.popFront();
                                        if (stringLiteral)
                                        {
                                            src = src.lexStringLiteral(idbuf, '"', STR.f);
                                            front = TOK.string;
                                            return;
                                        }
                                        else
                                            src = src.skipStringLiteral(bitbucket);
                                    }
                                    else
                                    {
                                        src.popFront();
                                        src = src.skipStringLiteral(bitbucket);
                                    }
                                    goto Lother;

                                default:
                                    break;
                            }
                        }
                        else if (src.front == '\'')
                        {
                            auto s = STR.s;
                            switch (cast(string)idbuf[])
                            {
                                case "L":       s = STR.L;  goto Lchar;
                                case "u":       s = STR.u;  goto Lchar;
                                case "u8":      s = STR.u8; goto Lchar;
                                case "U":       s = STR.U;  goto Lchar;
                                Lchar:
                                    static if (isContext)
                                    {
                                        src.expanded.on();
                                        src.expanded.put(idbuf[]);
                                        src.expanded.put(src.front);
                                    }
                                    src.popFront();
                                    src = src.lexCharacterLiteral(number.value, s);
                                    number.isunsigned = false;
                                    front = TOK.integer;
                                    return;

                                default:
                                    break;
                            }
                        }
                    }
                    goto Lident;

                Lother:
                    front = TOK.other;
                    return;

                case '\\':
                     // \u or \U could be start of identifier
                    src.popFront();
                    assert(0);   // not handled yet
                    break;

                case ESC.expand:
                    assert(0);   // not handled yet
                    break;

                default:
                    err_fatal("unrecognized preprocessor token");
                    src.popFront();
                    break;
            }
        }
    }
}

auto createLexer(R)(R r)
{
    Lexer!R lexer;
    lexer.src = r;
    lexer.popFront();   // 'prime' the pump
    return lexer;
}

unittest
{
  {
    auto s = cast(immutable(ubyte)[])(" \t\v\f\r" ~ ESC.space ~ ESC.brk);
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" + ++ += ");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.plus);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" - -- -= -> ->* ");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.minus);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" & && &= ");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.and);
    lexer.popFront();
    assert(lexer.front == TOK.andand);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" | || |= ");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.or);
    lexer.popFront();
    assert(lexer.front == TOK.oror);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])("(),?~{}[];:");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.lparen);
    lexer.popFront();
    assert(lexer.front == TOK.rparen);
    lexer.popFront();
    assert(lexer.front == TOK.comma);
    lexer.popFront();
    assert(lexer.front == TOK.question);
    lexer.popFront();
    assert(lexer.front == TOK.tilde);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.colon);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])("^^=**=%%=");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.xor);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.mul);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.mod);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])("> >= >>< <= << = == !!= . .. ... .*");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.gt);
    lexer.popFront();
    assert(lexer.front == TOK.ge);
    lexer.popFront();
    assert(lexer.front == TOK.shr);
    lexer.popFront();
    assert(lexer.front == TOK.lt);
    lexer.popFront();
    assert(lexer.front == TOK.le);
    lexer.popFront();
    assert(lexer.front == TOK.shl);
    lexer.popFront();
    assert(lexer.front == TOK.assign);
    lexer.popFront();
    assert(lexer.front == TOK.equal);
    lexer.popFront();
    assert(lexer.front == TOK.not);
    lexer.popFront();
    assert(lexer.front == TOK.notequal);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.dotdotdot);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" + // \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.plus);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" / /* */ /=");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.div);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" 100u \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.integer);
    assert(lexer.number.value == 100);
    assert(lexer.number.isunsigned);
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" \"123\" \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" abc $def _ehi \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.identifier && lexer.idbuf[] == "abc");
    lexer.popFront();
    assert(lexer.front == TOK.identifier && lexer.idbuf[] == "$def");
    lexer.popFront();
    assert(lexer.front == TOK.identifier && lexer.idbuf[] == "_ehi");
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" LR\"x(\")x\" R\"x(\")x\" u8R\"x(\")x\" uR\"x(\")x\" UR\"x(\")x\" \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" L\"a\" u\"a\" u8\"a\" U\"a\" LX\"a\" \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.identifier && lexer.idbuf[] == "LX");
    lexer.popFront();
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" 'a' L'a' u'a' u8'a' U'a' LX'a' \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.identifier && lexer.idbuf[] == "LX");
    lexer.popFront();
    assert(lexer.front == TOK.integer && lexer.number.value == 'a');
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" .088 \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eol);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
}
