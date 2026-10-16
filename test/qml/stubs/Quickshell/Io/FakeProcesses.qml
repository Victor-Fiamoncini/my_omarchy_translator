pragma Singleton

import QtQuick

// Answers the stub Processes. A test sets `respond` to a function from argv
// to the stdout to print, or to null to leave the process running (a hang).
// Without `respond`, nothing answers: qs.Commons' own hyprctl/fc-match calls
// simply never finish.
QtObject {
  property var commands: []
  property var respond: null

  function start(proc) {
    const argv = Array.from(proc.command)
    commands = commands.concat([argv])
    const out = respond ? respond(argv) : null
    if (out === null || out === undefined) return
    Qt.callLater(() => {
      if (!proc.running) return
      if (proc.stdout) {
        proc.stdout.text = out
        proc.stdout.streamFinished()
      }
      proc.running = false
      proc.exited(0, 0)
    })
  }

  function reset() {
    commands = []
    respond = null
  }
}
