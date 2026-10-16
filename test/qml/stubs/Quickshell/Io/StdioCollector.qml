import QtQuick

// Test stand-in for Quickshell.Io.StdioCollector.
QtObject {
  property string text: ""
  property bool waitForEnd: false

  signal streamFinished()
}
