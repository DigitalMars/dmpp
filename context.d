
/**
 * C preprocessor
 * Copyright: 2013 by Digital Mars
 * License: All Rights Reserved
 * Authors: Walter Bright
 */

import std.path;
import std.algorithm;
import std.array;

import cmdline;

/*********************************
 * Keep the state of the preprocessor in this struct.
 */

struct Context
{
    const Params params;        // command line parameters

    string[] paths;     // #include paths
    size_t sysIndex;    // paths[sysIndex] is start of system #includes

    bool errors;        // true if any errors occurred

    bool doDeps;        // true if doing dependency file generation
    char[] deps;        // dependency file contents

    /******
     * Construct global context from the command line parameters
     */
    this(ref const Params params)
    {
        this.params = params;
        this.doDeps = params.depFilename.length != 0;

        combineSearchPaths(params.includes, params.sysincludes, paths, sysIndex);
    }

    /**********
     * Create local context
     */
    void localStart(string sourceFilename)
    {
    }

    /**********
     * Preprocess a file
     */
    void preprocess()
    {
    }

    /**********
     * Finish local context
     */
    void localFinish()
    {
    }

    /**********
     * Finish global context
     */
    void globalFinish()
    {
        if (doDeps && !errors)
        {
            std.file.write(params.depFilename, deps);
        }
    }
}

/***********************************
 * Construct the total search path from the regular include paths and the
 * system include paths.
 * Input:
 *      includePaths    regular include paths
 *      sysIncludePaths system include paths
 * Output:
 *      paths           combined result
 *      sysIndex        paths[sysIndex] is where the system paths start
 */

void combineSearchPaths(const string[] includePaths, const string[] sysIncludePaths,
        out string[] paths, out size_t sysIndex)
{
    string[] incpaths;
    foreach (path; includePaths)
    {
        incpaths ~= split(path, pathSeparator);
    }

    string[] syspaths;
    foreach (path; sysIncludePaths)
    {
        syspaths ~= split(path, pathSeparator);
    }

    /* Concatenate incpaths[] and syspaths[] into paths[]
     * but remove from incpaths[] any that are also in syspaths[]
     */
    paths = incpaths.filter!((a) => find(syspaths, a).empty).array;
    sysIndex = paths.length;
    paths ~= syspaths;
}

unittest
{
    string[] paths;
    size_t sysIndex;

    combineSearchPaths(["a" ~ pathSeparator ~ "b","c","d"], ["e","c","f"], paths, sysIndex);
    assert(sysIndex == 3);
    assert(paths == ["a","b","d","e","c","f"]);
}
