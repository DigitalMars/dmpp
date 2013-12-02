
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module lexer;

import std.range;

import main;
import id;


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

    bool empty = false;

    void popFront()
    {
    }
}

