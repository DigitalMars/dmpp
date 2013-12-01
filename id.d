

/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

module id;

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

    /*********************
     * See if this is a known identifier.
     * Returns:
     *  Id*  if it is, null if not
     */
    static Id* search(ustring name)
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
        IDmacro      = 1,       // it's a macro in good standing
        IDdotdotdot  = 2,       // the macro has a ...
        IDfunctionLike = 4,     // the macro has ( ), i.e. is function-like
        IDpredefined = 8,       // the macro is specially predefined

        // Pragmas
        IDif         = 0x10,
        IDifdef      = 0x20,
        IDifndef     = 0x40,
        IDelif       = 0x80,
        IDelse       = 0x100,
        IDendif      = 0x200,
        IDinclude    = 0x400,
        IDundef      = 0x800,
        IDline       = 0x1000,
        IDerror      = 0x2000,
        IDpragma     = 0x4000,
        IDinclude_next = 0x800_0000,

        // Predefined
        IDlinnum     = 0x8000,
        IDfile       = 0x1_0000,
        IDfunc       = 0x2_0000,
        IDcounter    = 0x4_0000,
        IDfunction   = 0x8_0000,
        IDpretty_function = 0x10_0000,
        IDbase_file  = 0x20_0000,
        IDdate       = 0x40_0000,
        IDtime       = 0x80_0000,
        IDtimestamp  = 0x100_0000,
        IDcplusplus  = 0x200_0000,

        // Other
        IDdefined    = 0x400_0000,
    }

    ustring text;         // replacement text of the macro
    ustring[] parameters; // macro parameters
}
