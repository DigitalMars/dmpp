
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

// Deals with source file I/O

module sources;

import std.file;
import std.path;
import std.stdio;
import std.string;

import main;

/*********************************
 * Things to know about source files.
 */

struct SrcFile
{
    string filename;            // fully qualified file name
    ustring contents;           // contents of the file
    ustring includeGuard;       // macro #define used for #include guard
    bool once;                  // set if #pragma once set

    static SrcFile* lookup(string filename)
    {
        __gshared SrcFile[string] table;

        SrcFile sf;
        sf.filename = filename;
        auto p = filename in table;
        if (!p)
        {
            table[filename] = sf;
            p = filename in table;
        }
        return p;
    }

    /*******************************
     * Read a file and set its contents.
     */
    void read()
    {
        contents = cast(ustring)std.file.read(filename);
    }
}

/*********************************
 * Search for file along paths[].
 * Input:
 *      filename        file to look for
 *      paths[]         search paths
 *      starti          start searching at paths[starti]
 * Output:
 *      foundi          paths[index] is where the file was found,
 *                      paths.length if not in paths[]
 * Returns:
 *      fully qualified filename if found, null if not
 */

string fileSearch(string filename, string[] paths, size_t starti, out size_t foundi)
{
    foundi = paths.length;

    filename = strip(filename);

    if (isRooted(filename))
    {
    }
    else
    {
        foreach (key, path; paths[starti .. $])
        {
            auto name = buildPath(path, filename);
            if (exists(name))
            {   foundi = key;
                return buildNormalizedPath(name);
            }
        }
        return null;
    }
    filename = buildNormalizedPath(filename);
    return filename;
}

