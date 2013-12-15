

/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module id;

import core.stdc.stdio;
import core.stdc.time;

import main;

/******************************
 * All identifiers become a pointer to an instance
 * of this.
 */

struct Id
{
    __gshared Id*[ustring] table;

    ustring name;

    private this(ustring name)
    {
        this.name = name;
    }

    /******************************
     * Reset in between files processed.
     */
    static void reset()
    {
        /* Expect that the same headers will be processed again, with the
         * same macros. So leave the table in place - just #undef all the
         * entries.
         */
        foreach (m; table)
        {
            m.flags = 0;
            m.text = null;
            m.parameters = null;
        }
    }

    /*********************
     * See if this is a known identifier.
     * Returns:
     *  Id*  if it is, null if not
     */
    static Id* search(const(uchar)[] name)
    {
        auto p = name in table;
        return p ? *p : null;
    }


    /*************************
     * Look up name in Id table.
     * If it's there, return it.
     * If not, create an Id and return it.
     */
    static Id* pool(ustring name)
    {
        auto p = name in table;
        if (p)
            return *p;
        auto id = new Id(name);
        table[name] = id;
        return id;
    }

    /****************************
     * Define a macro.
     * Returns:
     *  null if a redefinition error
     */
    static Id* defineMacro(ustring name, ustring[] parameters, ustring text, uint flags)
    {
        auto m = pool(name);
        if (m.flags & IDmacro)
        {
            if ((m.flags ^ flags) & (IDpredefined | IDdotdotdot | IDfunctionLike) ||
                m.parameters != parameters ||
                text != text)
            {
                return null;
            }
        }
        m.flags |= IDmacro | flags;
        m.parameters = parameters;
        m.text = text;
        return m;
    }

    uint flags;         // flags are below
    enum
    {
        // Macros
        IDmacro        = 1,     // it's a macro in good standing
        IDdotdotdot    = 2,     // the macro has a ...
        IDfunctionLike = 4,     // the macro has ( ), i.e. is function-like
        IDpredefined   = 8,     // the macro is predefined and cannot be #undef'd
        IDinuse        = 0x10,  // macro is currently being expanded

        // Predefined
        IDlinnum       = 0x20,
        IDfile         = 0x40,
        IDcounter      = 0x80,
    }

    ustring text;         // replacement text of the macro
    ustring[] parameters; // macro parameters

    /* Initialize the predefined macros
     */
    static void initPredefined()
    {
        defineMacro(cast(ustring)"__FILE__", null, null, IDpredefined | IDfile);
        defineMacro(cast(ustring)"__LINE__", null, null, IDpredefined | IDlinnum);
        defineMacro(cast(ustring)"__COUNTER__", null, null, IDpredefined | IDcounter);

        uchar[1+26+1] date;
        time_t t;

        time(&t);
        auto p = cast(ubyte*)ctime(&t);
        assert(p);

        auto len = sprintf(cast(char*)date.ptr,"\"%.24s\"",p);
        defineMacro(cast(ustring)"__TIMESTAMP__", null, date[0..len].idup, IDpredefined);

        len = sprintf(cast(char*)date.ptr,"\"%.6s %.4s\"",p+4,p+20);
        defineMacro(cast(ustring)"__DATE__", null, date[0..len].idup, IDpredefined);

        len = sprintf(cast(char*)date.ptr,"\"%.8s\"",p+11);
        defineMacro(cast(ustring)"__TIME__", null, date[0..len].idup, IDpredefined);
    }
}
