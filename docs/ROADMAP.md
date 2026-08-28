# Roadmap

GEOBENCH has working CPC, MSX2, and PCW distributions. Completed platform and
format milestones belong in [Features](FEATURES.md) and the Git history rather
than in a growing checklist here.

## Current priorities

1. **Finish runtime hardening.** Continue converting user-visible long-running
   work to bounded root jobs or safe pure workers, and reduce unnecessary full
   desktop repaints. See [Preemptive multitasking](PREEMPTIVE_MULTITASKING.md)
   and the [application audit](PREEMPTIVE_APP_AUDIT.md).
2. **Application robustness.** Improve error reporting and resource lifecycle
   in Viewer, Browser, Paint, BASIC, and network applications. Viewer currently
   supports two simultaneous picture windows in the normal desktop flow; a
   third launch needs explicit resource handling and feedback.
3. **Desktop organization.** Add richer drawer/folder behavior and persistent
   spatial arrangement without enlarging the resident kernel unnecessarily.
4. **Modular configuration.** Add same-stem configuration modules only where a
   screensaver or application has useful options; keep Settings and the kernel
   independent of feature-specific controls.
5. **Platform validation.** Keep emulator tests paired with real-hardware checks
   for CPC storage/network boards, MSX mouse/joystick and UNAPI transports, and
   PCW floppy/serial hardware.

## Longer-term investigations

- A constrained MSX1 port, documented separately in [MSX1_port.md](MSX1_port.md).
- More app-carried 16-color icons and MSX Screen-7-aware application artwork.
- Additional external applications that use the reusable UI and document
  helpers without adding resident bytes.

This list is intentionally short. GitHub issues are the authority for scoped
implementation work and its acceptance criteria.
