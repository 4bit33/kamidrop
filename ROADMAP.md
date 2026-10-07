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
 └─ v0.1.4  ▸ English + language picker, README with screenshots

 ◐ NEXT ──────────────────────────────────────────────────────────────────────
 │
 └─ v0.2.0  ▸ ANDROID PRINT SERVICE                                   ★ priority
              ┌──────────────────────────────────────────────────────────────┐
              │ "Print" in Chrome / Photos / Gmail → KamiDrop printers       │
              │ ① Kotlin PrintService: printers, capabilities, jobs          │
              │ ② headless Flutter: print the system's PDF with our pipeline │
              │ ③ "Enable in print settings" button                          │
              │ ④ test: Chrome + Photos on a laser and an inkjet printer     │
              └──────────────────────────────────────────────────────────────┘

 ○ LATER (by usefulness) ─────────────────────────────────────────────────────
 │
 ├─ v0.2.x  ▸ subnet scan when mDNS is silent (isolated / hotspot networks)
 │          ▸ diagnostics screen: what the app sees on the network
 │          ▸ smarter "Share → print" (printer and settings picked automatically)
 │          ▸ one-tap copy: scan → print
 │          ▸ threshold slider for black & white scans
 │
 ├─ v0.3    ▸ DESKTOP: Linux and Windows (the core is plain Dart)
 │
 └─ someday ▸ IPP Everywhere / PWG raster (printers without AirPrint raster)
            ▸ direct JPEG printing where supported (faster, better photos)
            ▸ document photos 3×4 / 3.5×4.5 with cut lines

 ◌ OUTSIDE THE CODE ──────────────────────────────────────────────────────────
   ▸ report to sane-backends: Xerox WorkCentre 3225 is on the JPEG blacklist
   ▸ 2027: Android developer verification becomes mandatory → register when needed

   ● done     ◐ next     ○ planned     ◌ not code     ★ priority
```
