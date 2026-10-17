# Sources

Derek Ross, Omarchy Mobile, MIT:
https://github.com/derekross/omarchy-mobile/commit/1155a7c352edf6313fb4e2ff02f054c9cb1902b6
Bar and StatusModel copied from packages/omamobile-shell/plugins/omamobile.bar.
Spacewar adaptations and setup: MIT, 2026 Spacewar contributors.

Gesture contracts (fresh implementation; no Cube code vendored):
- https://github.com/SimonSchubert/omarchy-mobile/commit/08baab5c38573d0e65f74c362cdfd2a5a25e8399
  Shade/EdgeGestures input-region growth, progress without easing during drag,
  Carousel progress after release. MIT license retained in LICENSE.simon.
- https://github.com/Cube-Oakley/omarchy-mobile/commit/f702f688
  EdgeGestures pause-after-motion and PreviewGestures distance + velocity.
  No root LICENSE exists at the inspected source; the implementation here
  uses the documented interaction contract, not copied source text.

QuickSettings (including its editor, Wi-Fi/Bluetooth panels and sliders) and
Switcher copied from Derek's same commit and adapted for RU OSK and live drag.

Home (including complete OWL compiler/runtime/host), Launcher, omamobile-launch,
omamobile-widget and widget guide/examples: Derek 1155a7c352edf6313fb4e2ff02f054c9cb1902b6,
MIT. Runtime phone facts adapted to Spacewar; unknown refresh/dpi remain null.

OWL widget data: Simon Schubert and contributors, MIT, pinned b63886b as used
by Derek's omamobile-owl-widgets index. All 105 shipped files declare MIT;
LICENSE.widgets and the widget guide's LICENSE-owl-guide retain the notices.
https://github.com/SimonSchubert/omarchy-widgets/tree/b63886b
Each widget's original id, author, metadata, source and SHA256 are retained in
owl-widgets/index.json. No GPL-covered Squeekboard layout or other GPL source
was copied into this package; its license set is consequently MIT.

Bluetooth pairing agent and its pure-helper tests are also copied from Derek's
same pinned commit (MIT); runtime dependencies python-dbus/python-gobject are
explicit. No pairing with the laptop's devices was performed.
