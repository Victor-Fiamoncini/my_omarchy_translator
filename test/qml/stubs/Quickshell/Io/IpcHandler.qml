import QtQuick

// Test stand-in for Quickshell.Io.IpcHandler: no IPC in tests.
QtObject {
  property bool enabled: true
  property string target: ""
}
