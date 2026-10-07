# KamiDrop roadmap

**English** · [Українська](ROADMAP.uk.md)

```
 ● DONE ──────────────────────────────────────────────────────────────────────
 │
 ├─ v0.1.0  ▸ printer discovery (mDNS / NsdManager), PDF & photo printing over IPP
 │          ▸ AirPrint raster (URF), duplex, printer margins, edge-to-edge
 │          ▸ 1:1 layout editor (verified with a ruler), cancelling jobs
 │          ▸ signed APK, hanko icon, self-update from GitHub releases
 ├─ v0.1.1  ▸ photo sheets: cropping, two-finger gestures, page strip
 ├─ v0.1.2  ▸ scanning over eSCL → PDF, share / save / print
 ├─ v0.1.3  ▸ network scanners (incl. eSCL gateways), document feeder, PDF/JPEG/PNG
 ├─ v0.1.4  ▸ English + language picker, README with screenshots
 └─ v0.2.0  ▸ ANDROID PRINT SERVICE: KamiDrop printers in the system "Print" dialog
              of any app (Chrome, Photos, Gmail…), printed by our own pipeline

 ◐ NEXT ──────────────────────────────────────────────────────────────────────
 │
 └─ v0.2.x  ▸ "More options" in the system print dialog: fit / fill / 100 %,
            │ edge-to-edge, margins — our own screen inside the system dialog
            ▸ "ⓘ" next to a printer → KamiDrop: status, ink, scanning
            ▸ subnet scan when mDNS is silent (isolated / hotspot networks)
            ▸ diagnostics screen: what the app sees on the network
            ▸ smarter "Share → print" (printer and settings picked automatically)
            ▸ one-tap copy: scan → print
            ▸ threshold slider for black & white scans

 ○ LATER ─────────────────────────────────────────────────────────────────────
 │
 ├─ v0.3    ▸ DESKTOP: Linux and Windows (the core is plain Dart)
 │
 └─ someday ▸ IPP Everywhere / PWG raster (printers without AirPrint raster)
            ▸ direct JPEG printing where supported (faster, better photos)
            ▸ document photos 3×4 / 3.5×4.5 with cut lines

 ◌ OUTSIDE THE CODE ──────────────────────────────────────────────────────────
   ▸ report to sane-backends: Xerox WorkCentre 3225 is on the JPEG blacklist
   ▸ 2027: Android developer verification becomes mandatory → register when needed

   ● done     ◐ next     ○ planned     ◌ not code
```
