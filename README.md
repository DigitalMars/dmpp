# dmpp

**dmpp** is a C preprocessor. It reads source files in C or C++, and
generates a preprocessed output file.


## Options

Option                            | Description
------                            | -----------
*filename*...                     | source file name(s)
**-D** *name*[(*args*)][=*value*] | define macro *name*
**--dep** *filename*              | generate dependencies to output file
**-I** *path*                     | path to `#include` files
**--isystem** *path*              | path to system `#include` files
**-o** *filename*                 | preprocessed output file
**-v**                            | verbose


## Features:

* Will process multiple source files at the same time. This increases speed
because the contents of `#include` files are cached.

* If output files are not specified, a default file name is generated
from the source file name with the extension replaced with `.i`

* The only predefined macros are `__BASE_FILE__`, `__FILE__`, `__LINE__`, `__COUNTER__`,
`__TIMESTAMP__`, `__DATE__`, and `__TIME__`. Any others desired should be
set via the command line.

* **-v** uses the following codes for `#include` files:

Code | Description
---- | -----------
`S`  | system file
' '  | normal file read
`C`  | file read from cached copy
`O`  | file skipped because of `#pragma once`
`G`  | file skipped because of `#include` guard


## Extensions:

* supports `#pragma once`
* supports `#pragma GCC system_header`
* supports [linemarker](http://gcc.gnu.org/onlinedocs/cpp/Preprocessor-Output.html) output
* supports `,##__VA_ARGS__` extension which elides the comma
* `__COUNTER__` `__BASE_FILE__` predefined macros

## Bugs:

* trigraphs not supported
* digraphs not supported
* \u or \U in identifiers not supported
* C++ alternate keywords not supported
* multibyte Japanese, Chinese, or Korean characters not supported in source code
* Unicode (UTF8) not supported in source code

Copyright © 2021 by [Digital Mars](http://www.digitalmars.com)
[Boost License 1.0](http://boost.org/LICENSE_1_0.txt)

