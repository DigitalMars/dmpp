
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module textbuf;

import core.stdc.stdlib;
import core.stdc.string;
import std.stdio;

/**************************************
 * Textbuf encapsulates using a local array as a buffer.
 * It is initialized with the local array that should be large enough for
 * most uses. If the need exceeds the size, it will resize it
 * using malloc() and friends.
 */

//debug=Textbuf;

struct Textbuf(T, string id = null)
{
    this(T[] buf)
    {
        assert(!(buf.length & RESIZED));
        this.buf = buf.ptr;
        this.buflen = cast(uint)buf.length;
    }

    void put(T c)
    {
        const j = i;
        if (j == buflen)
        {
            resize(j * 2 + 16);
        }
        buf[j] = c;
        i = j + 1;
    }

    static if (T.sizeof == 1)
    {
        void put(dchar c)
        {
            put(cast(T)c);
        }

        void put(const(T)[] s)
        {
            const newlen = i + s.length;
            const len = buflen;
            if (newlen > len)
                resize(newlen <= len * 2 ? len * 2 : newlen);
            buf[i .. newlen] = s[];
            i = cast(uint)newlen;
        }
    }

    /******
     * Use this to retrieve the result.
     */
    T[] opSlice(size_t lwr, size_t upr)
    {
        assert(lwr <= buflen);
        assert(upr <= buflen);
        assert(lwr <= upr);
        return buf[lwr .. upr];
    }

    T[] opSlice()
    {
        assert(i <= buflen);
        return buf[0 .. i];
    }

    T opIndex(size_t i)
    {
        assert(i < buflen);
        return buf[i];
    }

    void initialize() { i = 0; }

    T last()
    {
        assert(i - 1 < buflen);
        return buf[i - 1];
    }

    T pop()
    {
        assert(i - 1 < buflen);
        return buf[--i];
    }

    @property size_t length()
    {
        return i;
    }

    void setLength(size_t i)
    {
        assert(i < buflen);
        this.i = cast(uint)i;
    }

    /**************************
     * Release any malloc'd data.
     */
    void free()
    {
        debug(Textbuf) buf[0 .. buflen] = 0;
        if (buflen & RESIZED)
            .free(buf);
        this = this.init;
    }

  private:
    T* buf;
    uint buflen;
    enum RESIZED = 1;         // this bit is set in buflen if we control the memory
    uint i;

    void resize(size_t newsize)
    {
        //writefln("%s: oldsize %s newsize %s", id, buf.length, newsize);
        void* p;
        newsize |= RESIZED;
        if (buflen & RESIZED)
        {
            /* Prefer realloc when possible
             */
            p = realloc(buf, newsize * T.sizeof);
            assert(p);
        }
        else
        {
            p = malloc(newsize * T.sizeof);
            assert(p);
            memcpy(p, buf, i * T.sizeof);
            debug(Textbuf) buf[0 .. buflen] = 0;
        }
        buf = cast(T*)p;
        buflen = cast(uint)newsize;

        /* Fake loop to prevent inlining. This function is called only rarely,
         * inlining results in poorer register allocation.
         */
        while (1) { break; }
    }
}

unittest
{
    char[2] buf = void;
    auto textbuf = Textbuf!char(buf);
    textbuf.put('a');
    textbuf.put('x');
    textbuf.put("abc");
    assert(textbuf.length == 5);
    assert(textbuf[1..3] == "xa");
    assert(textbuf[3] == 'b');
    textbuf.pop();
    assert(textbuf[0..textbuf.length] == "axab");
    textbuf.setLength(3);
    assert(textbuf[0..textbuf.length] == "axa");
    assert(textbuf.last() == 'a');
    assert(textbuf[1..3] == "xa");
    textbuf.put(cast(dchar)'z');
    assert(textbuf[] == "axaz");
    textbuf.initialize();
    assert(textbuf.length == 0);
    textbuf.free();
}
