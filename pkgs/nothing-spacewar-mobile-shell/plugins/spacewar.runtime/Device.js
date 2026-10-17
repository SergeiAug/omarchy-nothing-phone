// SPDX-License-Identifier: MIT
// LineageOS android_device_nothing_Spacewar overlay: config_mainBuiltInDisplayCutout
// M89.3,42.31 m0,26.19 a26.19,26.19 0 1,0 52.38,0 ... @left.
// Physical pixels / DSI-1 scale 2; reserve below the circle too, beyond the 44px bar.
var cutout = { x: 89.3 / 2, y: 42.31 / 2, diameter: 52.38 / 2 }
var safeLeft = Math.ceil(cutout.x + cutout.diameter + 8)
var safeTop = Math.ceil(cutout.y + cutout.diameter + 8)
if (typeof module !== "undefined") module.exports = {cutout:cutout, safeLeft:safeLeft, safeTop:safeTop}
