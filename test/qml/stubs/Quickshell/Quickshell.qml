pragma Singleton

import QtQuick

// Test stand-in for Quickshell's global: no environment, and detached
// commands are only recorded (tests read `detached`, then call reset()).
QtObject {
  property var detached: []

  function env(name) { return "" }

  function execDetached(argv) {
    detached = detached.concat([Array.from(argv)])
  }

  function reset() { detached = [] }
}
