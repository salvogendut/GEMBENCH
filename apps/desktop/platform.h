/* Select software policy independently of display/firmware architecture. */
#ifndef GB_DESKTOP_PLATFORM_H
#define GB_DESKTOP_PLATFORM_H
#if defined(GB_CPC_RESTART) && !defined(GB_DESKTOP_PROVIDER)
#error "CPC Desktop requires an explicit native provider"
#endif
#ifdef GB_DESKTOP_PROVIDER
#ifndef GB_PREEMPTIVE
#error "Native Desktop requires the installed preemptive core"
#endif
#define DESKTOP_NATIVE 1
#define GB_DESK_ACCESSORIES 1
#define GB_DEFER_MESSAGES 1
#define DESKTOP_SYSTEM_ITEM_COUNT 3
#else
#define DESKTOP_NATIVE 0
#define DESKTOP_SYSTEM_ITEM_COUNT 7
#endif
#endif
