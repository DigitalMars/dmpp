
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module constexpr;

import main;
import lexer;
import id;

/*****************************
 * Evaluate constant expressions for a boolean result.
 */

bool constantExpression(Lexer)(ref Lexer r)
{
    auto i = Comma(r);
    return i.value != 0;
}

private:

PPnumber Comma(Lexer)(ref Lexer r)
{
    auto i = Cond(r);
    while (r.front == TOK.comma)
    {
        r.popFront();
        i = Cond(r);
    }
    return i;
}

PPnumber Cond(Lexer)(ref Lexer r)
{
    auto i = OrOr(r);
    if (r.front == TOK.cond)
    {
        r.popFront();
        auto i1 = Comma(r);
        if (r.front != TOK.colon)
            err_fatal(": expected");
        auto i2 = Cond(r);
        return i.value ? i1 : i2;
    }
    return i;
}

PPnumber OrOr(Lexer)(ref Lexer r)
{
    auto i = AndAnd(r);
    while (r.front == TOK.oror)
    {
        r.popFront();
        auto i2 = AndAnd(r);
        i.value = i.value || i2.value;
        i.isunsigned = false;
    }
    return i;
}

PPnumber AndAnd(Lexer)(ref Lexer r)
{
    auto i = Or(r);
    while (r.front == TOK.andand)
    {
        r.popFront();
        auto i2 = Or(r);
        i.value = i.value && i2.value;
        i.isunsigned = false;
    }
    return i;
}

PPnumber Or(Lexer)(ref Lexer r)
{
    auto i = Xor(r);
    while (r.front == TOK.or)
    {
        r.popFront();
        auto i2 = Xor(r);
        i.value |= i2.value;
        i.isunsigned |= i2.isunsigned;
    }
    return i;
}

PPnumber Xor(Lexer)(ref Lexer r)
{
    auto i = And(r);
    while (r.front == TOK.xor)
    {
        r.popFront();
        auto i2 = And(r);
        i.value ^= i2.value;
        i.isunsigned |= i2.isunsigned;
    }
    return i;
}


PPnumber And(Lexer)(ref Lexer r)
{
    auto i = Equal(r);
    while (r.front == TOK.and)
    {
        r.popFront();
        auto i2 = Equal(r);
        i.value &= i2.value;
        i.isunsigned |= i2.isunsigned;
    }
    return i;
}


PPnumber Equal(Lexer)(ref Lexer r)
{
    auto i = Cmp(r);
    while (1)
    {
        switch (r.front)
        {
            case TOK.equal:
                r.popFront();
                auto i2 = Cmp(r);
                i.value = i.value == i2.value;
                i.isunsigned = false;
                continue;

            case TOK.notequal:
                r.popFront();
                auto i2 = Cmp(r);
                i.value = i.value != i2.value;
                i.isunsigned = false;
                continue;

             default:
                break;
        }
    }
    return i;
}



PPnumber Cmp(Lexer)(ref Lexer r)
{
    auto i = Shift(r);
    while (1)
    {
        switch (r.front)
        {
            case TOK.le:
                r.popFront();
                auto i2 = Shift(r);
                if (i.isunsigned || i2.isunsigned)
                    i.value = i.value <= cast(ppuint_t)i2.value;
                else
                    i.value = i.value <= i2.value;
                i.isunsigned = false;
                continue;

            case TOK.lt:
                r.popFront();
                auto i2 = Shift(r);
                if (i.isunsigned || i2.isunsigned)
                    i.value = i.value < cast(ppuint_t)i2.value;
                else
                    i.value = i.value < i2.value;
                i.isunsigned = false;
                continue;

            case TOK.ge:
                r.popFront();
                auto i2 = Shift(r);
                if (i.isunsigned || i2.isunsigned)
                    i.value = i.value >= cast(ppuint_t)i2.value;
                else
                    i.value = i.value >= i2.value;
                i.isunsigned = false;
                continue;

            case TOK.gt:
                r.popFront();
                auto i2 = Shift(r);
                if (i.isunsigned || i2.isunsigned)
                    i.value = i.value > cast(ppuint_t)i2.value;
                else
                    i.value = i.value > i2.value;
                i.isunsigned = false;
                continue;

             default:
                break;
        }
    }
    return i;
}

PPnumber Shift(Lexer)(ref Lexer r)
{
    auto i = Add(r);
    while (1)
    {
        switch (r.front)
        {
            case TOK.shl:
                r.popFront();
                auto i2 = Add(r);
                i.value = i.value << i2.value;
                continue;

            case TOK.shr:
                r.popFront();
                auto i2 = Add(r);
                if (i.isunsigned)
                    i.value = cast(ppuint_t)i.value >> i2.value;
                else
                    i.value = i.value >> i2.value;
                continue;

             default:
                break;
        }
    }
    return i;
}


PPnumber Add(Lexer)(ref Lexer r)
{
    auto i = Mul(r);
    while (1)
    {
        switch (r.front)
        {
            case TOK.add:
                r.popFront();
                auto i2 = Mul(r);
                i.value = i.value + i2.value;
                i.isunsigned |= i2.isunsigned;
                continue;

            case TOK.sub:
                r.popFront();
                auto i2 = Mul(r);
                i.value = i.value - i2.value;
                i.isunsigned |= i2.isunsigned;
                continue;

             default:
                break;
        }
    }
    return i;
}


PPnumber Mul(Lexer)(ref Lexer r)
{
    auto i = Unary(r);
    while (1)
    {
        switch (r.front)
        {
            case TOK.mul:
                r.popFront();
                auto i2 = Unary(r);
                i.value = i.value * i2.value;
                i.isunsigned |= i2.isunsigned;
                continue;

            case TOK.div:
                r.popFront();
                auto i2 = Unary(r);
                if (i2.value)
                {
                    i.isunsigned |= i2.isunsigned;
                    if (i.usunsigned)
                        i.value /= cast(ppuint_t)i2.value;
                    else
                        i.value /= i2.value;
                }
                else
                    err_fatal("divide by zero");
                continue;

            case TOK.mod:
                r.popFront();
                auto i2 = Unary(r);
                if (i2)
                {
                    i.isunsigned |= i2.isunsigned;
                    if (i.usunsigned)
                        i.value %= cast(ppuint_t)i2.value;
                    else
                        i.value %= i2.value;
                }
                else
                    err_fatal("divide by zero");
                continue;

             default:
                break;
        }
    }
    return i;
}



PPnumber Unary(Lexer)(ref Lexer r)
{
    switch (r.front)
    {
        case TOK.add:
            r.popFront();
            return Unary(r);

        case TOK.min:
        {
            r.popFront();
            auto i = Unary(r);
            i.value = -i.value;
            return i;
        }

        case TOK.not:
        {
            r.popFront();
            auto i = Unary(r);
            i.value = !i.value;
            i.isunsigned = false;
            return i;
        }

        case TOK.com:
        {
            r.popFront();
            auto i = Unary(r);
            i.value = ~i.value;
            return i;
        }

        case TOK.lparen:
        {
            r.popFront();
            auto i = Comma(r);
            if (r.front != TOKrparen)
                err_fatal(") expected");
            r.popFront();
            return i;
        }

        default:
            return Primary(r);
    }
}

PPnumber Primary(Lexer)(ref Lexer r)
{
    switch (r.front)
    {
        case TOK.ident:
            break;

        case TOK.defined:
            r.popFront();
            if (r.front != TOK.ident)
                err_fatal("identifier expected");
            else
            {
                if (r.id.flags & IDmacro)
                {
                    PPnumber i;
                    i.value = 1;
                    return i;
                }
            }
            break;

        case TOK.integer:
        {
            auto i = r.number();
            r.popFront();
            return i;
        }

        default:
            err_fatal("primary expression expected");
            break;
    }
    r.popFront();
    return PPnumber();          // i.e. return signed 0
}
