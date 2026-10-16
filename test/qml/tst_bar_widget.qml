import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// The bar pill (BarWidget.qml) with a stand-in bar: what each mouse button
// does. Quickshell is stubbed (test/qml/stubs), so detached commands are only
// recorded. Run by script/test-qml.
TestCase {
  id: testCase
  name: "BarWidget"
  width: 200
  height: 100
  // TestCase is hidden by default, and hidden items get no mouse events.
  visible: true
  when: windowShown

  // The members of Omarchy's bar object that the widget and its button use.
  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 32
    property string position: "top"
    property string fontFamily: "monospace"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
  }

  property var widget: null

  function init() {
    FakeProcesses.reset()
    Quickshell.reset()
    widget = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../BarWidget.qml")), testCase,
                                   { bar: fakeBar })
    verify(widget, "BarWidget.qml did not load")
    tryVerify(() => widget.width > 0)
  }

  function test_cli_is_the_bundled_executable() {
    verify(widget.cli.endsWith("/bin/omarchy-translate"), widget.cli)
    verify(widget.cli.startsWith("/"), widget.cli)
  }

  function test_right_click_translates_the_clipboard_into_a_notification() {
    mouseClick(widget, widget.width / 2, widget.height / 2, Qt.RightButton)

    compare(Quickshell.detached, [["bash", "-lc", 'exec "$@"', "bash", widget.cli, "--clipboard", "--notify"]])
  }

  function test_middle_click_pipes_a_screen_region_through_ocr() {
    mouseClick(widget, widget.width / 2, widget.height / 2, Qt.MiddleButton)

    compare(Quickshell.detached.length, 1)
    const argv = Quickshell.detached[0]
    compare(argv.slice(0, 2), ["bash", "-lc"])
    verify(argv[2].includes("slurp") && argv[2].includes("tesseract") && argv[2].endsWith('| "$0" --notify'))
    compare(argv[3], widget.cli)
  }

  function test_left_click_opens_and_closes_the_popup() {
    mouseClick(widget, widget.width / 2, widget.height / 2)

    tryVerify(() => widget.opened)
    verify(FakeProcesses.commands.some(argv => argv[0] === widget.cli && argv[1] === "--status"))

    mouseClick(widget, widget.width / 2, widget.height / 2)

    verify(!widget.opened)
  }
}
