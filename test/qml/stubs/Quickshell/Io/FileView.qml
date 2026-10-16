import QtQuick

// Test stand-in for Quickshell.Io.FileView: never loads, so qs.Commons keeps its defaults.
QtObject {
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true

  signal loaded()
  signal loadFailed(int error)
  signal fileChanged()

  function text() { return "" }
  function reload() {}
}
