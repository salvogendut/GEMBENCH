/* Software policy selection is separate from hardware geometry/graphics.
 * New native profiles must bind their I/O explicitly. Never fall through to
 * the inherited CPC firmware/filesystem/window-manager path. */
#ifndef GB_FILEMGR_PLATFORM_H
#define GB_FILEMGR_PLATFORM_H
#if defined(GB_CPC_RESTART) && !defined(GB_FILEMGR_PROVIDER)
#error "CPC File Manager requires an explicit native provider"
#endif
#ifdef GB_FILEMGR_PROVIDER
#ifndef GB_PREEMPTIVE
#error "Native File Manager profile requires shared preemptive dispatch"
#endif
#define FM_NATIVE_IO 1
#define FM_SHARED_CORE 1
#define FM_FILE_COPY 0
#define FM_EMBEDDED_ICONS 0
#define GB_NATIVE_WINDOW_KIND 1
#else
#define FM_NATIVE_IO 0
#define FM_FILE_COPY 1
#define FM_EMBEDDED_ICONS 1
#ifdef GB_MSX2
#define FM_SHARED_CORE 1
#else
#define FM_SHARED_CORE 0
#endif
#endif
#endif
