#include <android/log.h>

#pragma GCC visibility push(default)
extern "C" {

int __android_log_write(int prio, const char* tag, const char* text)
{
   return 0;
}

int __android_log_print(int prio, const char* tag, const char* fmt, ...)
{
   return 0;
}

}
#pragma GCC visibility pop
