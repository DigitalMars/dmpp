
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module textbuf;

import core.stdc.stdlib;
import core.stdc.string;

/**************************************
 * Textbuf encapsulates using a local array as a buffer.
 * It is initialized with the local array that should be large enough for
 * most uses. If the need exceeds the size, it will resize it
 * using malloc() and friends.
 */
struct Textbuf(T)
{
    this(T[] buf)
    {
        this.buf = buf;
    }

    void put(T c)
    {
        if (i == buf.length)
        {
            resize(i ? i * 2 : 16);
        }
        buf[i++] = c;
    }

    void put(dchar c)
    {
        put(cast(T)c);
    }

    void put(const(T)[] s)
    {
        size_t newlen = i + s.length;
        if (newlen > buf.length)
            resize(newlen <= buf.length * 2 ? buf.length * 2 : newlen);
        buf[i .. newlen] = s[];
        i = newlen;
    }

    /******
     * Use this to retrieve the result.
     */
    T[] opSlice(size_t lwr, size_t upr)
    {
        return buf[lwr .. upr];
    }

    T[] opSlice()
    {
        return buf[0 .. i];
    }

    T opIndex(size_t i)
    {
        return buf[i];
    }

    void initialize() { i = 0; }

    T last()
    {
        return buf[i - 1];
    }

    T pop()
    {
        return buf[--i];
    }

    @property size_t length()
    {
        return i;
    }

    void setLength(size_t i)
    {
        this.i = i;
    }

    /**************************
     * Release any malloc'd data.
     */
    void free()
    {
        if (resized)
            .free(buf.ptr);
        this = this.init;
    }

  private:
    T[] buf;
    size_t i;
    bool resized;

    void resize(size_t newsize)
    {
        void* p;
        if (resized)
        {
            /* Prefer realloc when possible
             */
            p = realloc(buf.ptr, newsize);
            assert(p);
        }
        else
        {
            p = malloc(newsize);
            assert(p);
            memcpy(p, buf.ptr, i);
            resized = true;
        }
        buf = (cast(T*)p)[0 .. newsize];
    }
}

unittest
{
    char[1] buf = void;
    auto textbuf = Textbuf!char(buf);
    textbuf.put('a');
    textbuf.put('x');
    textbuf.put("abc");
    assert(textbuf.length == 5);
    assert(textbuf[1..3] == "xa");
    assert(textbuf[3] == 'b');
    textbuf.pop();
    assert(textbuf[0..textbuf.length] == "axab");
    textbuf.free();
}
