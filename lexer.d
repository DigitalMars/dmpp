
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module lexer;

import std.array;
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

    integer,
    identifier,
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
    Id* ident;

    alias Unqual!(ElementEncodingType!R) E;
    R src;
    BitBucket!E bitbucket;

    StaticArrayBuffer!(E, 1024) idbuf = void;

    enum empty = false;         // return TOK.eof for going off the end

    void popFront()
    {
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
                    front = TOK.eof;
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
                                src = src.skipFloat(false, true, false);
                                break;

                            case '*':
                                src.popFront();
                                break;

                            case '.':
                                src.popFront();
                                if (!src.empty && src.front == '.')
                                {
                                    src.popFront();
                                    goto Lother;
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
                    goto Lother;

                case '<':
                    src.popFront();
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
                    src = src.skipStringLiteral(bitbucket);
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
                    idbuf.init();
                    src = src.inIdentifier(idbuf);
                Lident:
                    front = TOK.identifier;
                    return;

                case 'L':
                case 'u':
                case 'U':
                case 'R':
                    // string prefixes: L LR u u8 uR u8R U UR R
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
                                    src.popFront();
                                    src = src.skipRawStringLiteral(bitbucket);
                                    goto Lother;

                                case "L":
                                case "u":
                                case "u8":
                                case "U":
                                    src.popFront();
                                    src = src.skipStringLiteral(bitbucket);
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
    assert(lexer.front == TOK.other);
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
    assert(lexer.front == TOK.other);
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
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" \"123\" \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
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
    assert(lexer.front == TOK.eof);
  }
  {
    auto s = cast(immutable(ubyte)[])(" .088 \n");
    auto lexer = createLexer(s);
    assert(!lexer.empty);
    assert(lexer.front == TOK.other);
    lexer.popFront();
    assert(lexer.front == TOK.eof);
  }
}
