//
//  ConstructorHost-Bridging-Header.h
//  ConstructorHost
//
//  Bridging header exposing C-ABI runtime utilities and the official Libretro API to Swift.
//

#ifndef ConstructorHost_Bridging_Header_h
#define ConstructorHost_Bridging_Header_h

#include <dlfcn.h>      // POSIX dynamic library symbols: dlopen, dlsym, dlclose, dlerror
#include <stdlib.h>     // POSIX memory management: malloc, free, strdup
#include <string.h>     // C string manipulation: strlen, strcmp
#include "libretro.h"   // Official Libretro specification (structures, enums, function pointers)

#endif /* ConstructorHost_Bridging_Header_h */
