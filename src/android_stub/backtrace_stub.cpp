#include <backtrace/Backtrace.h>

#pragma GCC visibility push(default)
Backtrace*
Backtrace::Create(pid_t pid, pid_t tid, BacktraceMap* map)
{
   return NULL;
}

std::string
backtrace_map_t::Name() const
{
   return "";
}
#pragma GCC visibility pop

