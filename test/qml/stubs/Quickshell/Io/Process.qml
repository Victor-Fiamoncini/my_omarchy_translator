import QtQuick

// Test stand-in for Quickshell.Io.Process: starting it hands it to
// FakeProcesses, which answers with the stdout a test chose.
QtObject {
  id: root

  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  property var environment: ({})
  property string workingDirectory: ""

  signal started()
  signal exited(int exitCode, int exitStatus)

  onRunningChanged: if (running) FakeProcesses.start(root)
}
