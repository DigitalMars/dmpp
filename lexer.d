
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

import main;
import id;
import macros;


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
alias long ppuint_t;

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
            src.popFront();
            switch (c)
            {
                case ' ':
                case '\t':
                case '\r':
                case '\v':
                case '\f':
                case ESC.space:
                case ESC.brk:
                    continue;

                case '\n':
                    front = TOK.eof;
                    return;

                case '0': .. case '9':
                    lexNumber(c);
                    front = TOK.integer;
                    return;

                case '.':
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '0': .. case '9':
                                lexFloat(c);
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
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.notequal;
                        return;
                    }
                    front = TOK.not;
                    return;

                case '=':
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        front = TOK.equal;
                        return;
                    }
                    goto Lother;

                case '<':
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
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.mod;
                    return;

                case '*':
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.mul;
                    return;

                case '^':
                    if (!src.empty && src.front == '=')
                    {
                        src.popFront();
                        goto Lother;
                    }
                    front = TOK.xor;
                    return;

                case '+':
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
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                                src.popFront();
                                break;

                            case '&':
                                src.popFront();
                                front = TOK.andand;
                                return;

                            default:
                                front = TOK.and;
                                return;
                        }
                    }
                    goto Lother;

                case '|':
                    if (!src.empty)
                    {
                        switch (src.front)
                        {
                            case '=':
                                src.popFront();
                                break;

                            case '|':
                                src.popFront();
                                front = TOK.oror;
                                return;

                            default:
                                front = TOK.or;
                                return;
                        }
                    }
                    goto Lother;

                case '(':    front = TOK.lparen;    return;
                case ')':    front = TOK.rparen;    return;
                case ',':    front = TOK.comma;     return;
                case '?':    front = TOK.question;  return;
                case '~':    front = TOK.tilde;     return;

                case '{':
                case '}':
                case '[':
                case ']':
                    goto Lother;

                case '\\':
                case '/':
                case ':':
                case ';':
                case '"':
                case '\'':
                case ESC.expand:
                    goto Lother;

                Lother:
                    front = TOK.other;
                    return;

                default:
                    err_fatal("unrecognized preprocessor token");
                    break;
            }
        }
    }

    void lexNumber(E c)
    {
    }

    void lexFloat(E c)
    {
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
    auto s = cast(immutable(ubyte)[])("(),?~{}[]");
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
}
