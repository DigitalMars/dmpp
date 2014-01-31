
/****
 * Generic ranges not found in Phobos.
 * Copyright: 2013 by Digital Mars
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Walter Bright
 */

module ranges;

/**************
 * BitBucket is an OutputRange that throws away its output.
 */

struct BitBucket(E)
{
    static void put(E e) { }
}

/*****************************************
 */

struct EmptyInputRange(E)
{
    enum bool empty = true;

    enum E front = E.init;

    static void popFront() { assert(0); }
}

/*****************************************
 */

struct StaticArrayBuffer(E, size_t N)
{
    E[N] arr = void;
    size_t i;

    void init() { i = 0; }

    void put(E e)
    {
        arr[i] = e;
        ++i;
    }

    E[] opSlice()
    {
        return arr[0 .. i];
    }

    @property size_t length() { return i; }
}

//import std.stdio;

unittest
{
    StaticArrayBuffer!(ubyte, 2) buf = void;
    buf.init();
    buf.put('a');
    buf.put('b');
//writefln("'%s'", buf.get());
    assert(buf[] == "ab");
}

unittest
{
    ubyte[2] buf = void;
    size_t i;
    buf[i] = 'a';
    ++i;
    buf[i] = 'b';
    ++i;
    assert(buf[0 .. i] == "ab");
}
