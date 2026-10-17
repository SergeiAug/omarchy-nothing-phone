// SPDX-License-Identifier: MIT
import QtQuick
MultiPointTouchArea {
  id: input
  minimumTouchPoints: 1; maximumTouchPoints: 2
  mouseEnabled: true
  property bool blocked: false
  property bool tracking: false
  signal began(real x, real y)
  signal moved(real x, real y)
  signal ended(bool canceled)
  touchPoints: [TouchPoint { id: first }, TouchPoint { id: second }]
  function cancel() {
    if (tracking) { tracking = false; ended(true) }
    blocked = true
  }
  onPressed: {
    if (second.pressed) { cancel(); return }
    if (!blocked && !tracking) { tracking = true; began(first.x, first.y) }
  }
  onUpdated: {
    if (second.pressed) cancel()
    else if (tracking) moved(first.x, first.y)
  }
  onReleased: {
    if (!first.pressed && tracking) { tracking = false; ended(false) }
    if (!first.pressed && !second.pressed) blocked = false
  }
  onCanceled: { cancel(); blocked = false }
  onEnabledChanged: if (!enabled) { cancel(); blocked = false }
}
