#include <hardware/hardware.h>

#pragma GCC visibility push(default)
extern "C" {

int hw_get_module(const char *id, const struct hw_module_t **module)
{
   return 0;
}

}
#pragma GCC visibility pop
