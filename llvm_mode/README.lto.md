# afl-clang-lto - collision free instrumentation at link time

## TLDR;

1. Use afl-clang-lto/afl-clang-lto++ because it is faster and gives better
   coverage than anything else that is out there in the AFL world

2. You can use it together with llvm_mode: laf-intel and whitelisting
   features and can be combined with cmplog/Redqueen

3. It only works with llvm 9 (and likely 10+ but is not tested there yet)

## Introduction and problem description

A big issue with how afl/afl++ works is that the basic block IDs that are
set during compilation are random - and hence natually the larger the number
of instrumented locations, the higher the number of edge collisions in the
map. This can result in not discovering new paths and therefore degrade the
efficiency of the fuzzing.

*This issue is understimated in the fuzzing community!*
With a 2^16 = 64kb standard map at already 256 instrumented blocks there is
on average one collision. On average a target has 10.000 to 50.000
instrumented blocks hence the real collisions are between 750-18.000!

To get to a solution that prevents any collision took several approaches
and many dead ends until we got to this:

 * We instrument at link time when we have all files pre-compiled
 * To instrument at link time we compile in LTO (link time optimization) mode
 * Our compiler (afl-clang-lto/afl-clang-lto++) takes care of setting the
   correct LTO options and runs our own afl-ld linker instead of the system
   linker
 * Our linker collects all LTO files to link and instruments them so that
   we have non-colliding edge overage
 * We use a new (for afl) edge coverage - which is the same as in llvm
   -fsanitize=coverage edge coverage mode :)
 * after inserting our instrumentation in all interesting edges we link
   all parts of the program together to our executable

The result:
 * 10-15% speed gain compared to llvm_mode
 * guaranteed non-colliding edge coverage :-)
 * The compile time especially for libraries can be longer

Example build output from a libtiff build:
```
/bin/bash ../libtool  --tag=CC   --mode=link afl-clang-lto  -g -O2 -Wall -W   -o thumbnail thumbnail.o ../libtiff/libtiff.la ../port/libport.la -llzma -ljbig -ljpeg -lz -lm 
libtool: link: afl-clang-lto -g -O2 -Wall -W -o thumbnail thumbnail.o  ../libtiff/.libs/libtiff.a ../port/.libs/libport.a -llzma -ljbig -ljpeg -lz -lm
afl-clang-lto++2.62d by Marc "vanHauser" Heuse <mh@mh-sec.de>
afl-ld++2.62d by Marc "vanHauser" Heuse <mh@mh-sec.de> (level 0)
[+] Running ar unpacker on /prg/tests/lto/tiff-4.0.4/tools/../libtiff/.libs/libtiff.a into /tmp/.afl-3914343-1583339800.dir
[+] Running ar unpacker on /prg/tests/lto/tiff-4.0.4/tools/../port/.libs/libport.a into /tmp/.afl-3914343-1583339800.dir
[+] Running bitcode linker, creating /tmp/.afl-3914343-1583339800-1.ll
[+] Performing optimization via opt, creating /tmp/.afl-3914343-1583339800-2.bc
[+] Performing instrumentation via opt, creating /tmp/.afl-3914343-1583339800-3.bc
afl-llvm-lto++2.62d by Marc "vanHauser" Heuse <mh@mh-sec.de>
[+] Instrumented 15833 locations with no collisions (on average 1767 collisions would be in afl-gcc/afl-clang-fast) (non-hardened mode).
[+] Running real linker /bin/x86_64-linux-gnu-ld
[+] Linker was successful
```

## How to use afl-clang-lto

Just use afl-clang-lto like you did afl-clang-fast or afl-gcc.

Also whitelisting (AFL_LLVM_WHITELIST -> [README.whitelist.md](README.whitelist.md)) and
laf-intel/compcov (AFL_LLVM_LAF_* -> [README.laf-intel.md](README.laf-intel.md)) work.
Instrim does not - but we can not really use it anyway for our approach.

Example:
```
CC=afl-clang-lto CXX=afl-clang-lto++ ./configure
make
```

## Potential issues

### compiling libraries fails

If you see this message:
```
/bin/ld: libfoo.a: error adding symbols: archive has no index; run ranlib to add one
```
This is because usually gnu gcc ranlib is being called which cannot deal with clang LTO files.
The solution is simple: when you ./configure you have also have to set RANLIB=llvm-ranlib and AR=llvm-ar

Solution:
```
AR=llvm-ar RANLIB=llvm-ranlib CC=afl-clang-lto CXX=afl-clang-lto++ ./configure --disable-shared
```
and on some target you have to to AR=/RANLIB= even for make as the configure script does not save it ...

### clang is hardcoded to /bin/ld

Some clang packages have 'ld' hardcoded to /bin/ld. This is an issue as this
prevents "our" afl-ld being called.

-fuse-ld=/path/to/afl-ld should be set through makefile magic in llvm_mode - 
if it is supported - however if this fails you can try:
```
LDFLAGS=-fuse-ld=</path/to/afl-ld
```

As workaround attempt #2 you will have to switch /bin/ld:
```
  mv /bin/ld /bin/ld.orig
  cp afl-ld /bin/ld
```
This can result in two problems though:

 !1!
  When compiling afl-ld, the build process looks at where the /bin/ld link
  is going to. So when the workaround was applied and a recompiling afl-ld
  is performed then the link is gone and the new afl-ld clueless where
  the real ld is.
  In this case set AFL_REAL_LD=/bin/ld.orig

 !2! 
 When you install an updated gcc/clang/... package, your OS might restore
 the ld link.

### compiling programs still fail

afl-clang-lto is still work in progress.
Complex targets are still likely not to compile and this needs to be fixed.
Please report issues at:
[https://github.com/vanhauser-thc/AFLplusplus/issues/226](https://github.com/vanhauser-thc/AFLplusplus/issues/226)

Known issues:
* ffmpeg
* bogofilter
* libjpeg-turbo-1.3.1

## Upcoming Work

1. Currently the LTO whitelist feature does not allow to not instrument main, start and init functions
2. Modify the forkserver + afl-fuzz so that only the necessary map size is
   loaded and used - and communicated to afl-fuzz too.
   Result: faster fork in the target and faster map analysis in afl-fuzz
   => more speed :-)

## Tested and working targets

* libpng-1.2.53
* libxml2-2.9.2
* tiff-4.0.4
* unrar-nonfree-5.6.6
* exiv 0.27
* jpeg-6b
