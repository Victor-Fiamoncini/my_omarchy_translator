# QML basics: a hands-on tutorial

A beginner's guide to QML, the language the Translator's `BarWidget.qml` and
`Panel.qml` are written in. It doesn't assume you know Qt. If you know some
JavaScript, HTML/CSS or a UI framework like React, you'll recognise a lot of it.

[HOW_IT_WORKS.md](HOW_IT_WORKS.md) gives a 10-minute version that is tied to this
project. This one goes slower, covers more, and every example runs on its own.

---

## 0. Running the examples

Every example that starts with `import QtQuick` and has a `Window` at the top is a
complete program. Save it as, for example, `hello.qml` and run it:

```sh
qml6 hello.qml                        # Qt 6's QML runner, already installed on Omarchy
/usr/lib/qt6/bin/qmllint hello.qml    # optional: static checks
```

> Use **`qml6`**, not `qml`. On this system `/usr/bin/qml` is the old **Qt 5**
> runner. Qt 5 requires versioned imports (`import QtQuick 2.15`), so it rejects
> these files with "Did not load any objects". Quickshell and Omarchy use Qt 6.

Edit the file, close the window and run it again. Experimenting this way is the
fastest way to learn.

---

## 1. What QML is

QML (*Qt Modeling Language*) is a **declarative** language for describing user
interfaces. Instead of writing step-by-step code that creates widgets ("create a
button, set its text, add it to the window…"), you describe the tree of objects
you want. The QML engine builds that tree and keeps it up to date.

You'll see three pieces:

| Piece | What it is | Web analogy |
|---|---|---|
| **QML syntax** | Object tree with properties | HTML + CSS |
| **JavaScript** | Expressions, functions, event handlers | JS |
| **Qt Quick** | The library of visual types: `Rectangle`, `Text`, `MouseArea`… | The DOM elements |

The engine is C++ and drawing is done on the GPU. Your QML file only describes
what should be on screen and how it should react.

---

## 2. Your first file

```qml
import QtQuick

Window {
  width: 320
  height: 200
  visible: true
  title: "Hello"

  Text {
    text: "Hello, QML!"
    font.pixelSize: 24
    anchors.centerIn: parent
  }
}
```

The parts:

- **`import QtQuick`** loads a *module*, which is a package of types. Without it,
  `Window` and `Text` don't exist.
- **`Window { … }`** creates an *object* of type `Window`. A type name always
  starts with a capital letter.
- **`width: 320`** sets a *property*. The syntax is `name: value`, with no
  semicolon needed.
- **`Text { … }`** inside `Window` is a *child object*, so nesting gives you the
  tree.
- **`font.pixelSize`** is a *grouped property*. `font` has its own
  sub-properties. You can also write `font { pixelSize: 24; bold: true }`.
- **`anchors.centerIn: parent`** places the text relative to its parent (see
  §6).

Every QML file has **exactly one root object**. Here it's the `Window`.

---

## 3. Properties

Each type comes with built-in properties (`width`, `color`, `text`, `visible`,
`opacity`…). You can declare your own as well:

```qml
import QtQuick

Window {
  id: win
  width: 320; height: 200; visible: true

  property int clicks: 0                  // typed, with an initial value
  property string name: "Victor"
  property bool loud: false
  property var anything: ({ a: 1 })       // var holds any JS value
  readonly property string greeting: "Hi " + name

  Text {
    anchors.centerIn: parent
    text: win.loud ? win.greeting.toUpperCase() : win.greeting
  }
}
```

Common types are `int`, `real`, `bool`, `string`, `color`, `url`, `var`, `list<…>`,
and any object type (`property Item target`).

> **Gotcha:** `property var x: ({ a: 1 })` needs the parentheses. Without them,
> `{ a: 1 }` is parsed as a block of code, not an object literal.

---

## 4. `id`: naming objects

An `id` gives an object a name that the rest of the file can use:

```qml
Rectangle { id: box; width: 100; height: 100; color: "teal" }
Text { text: "Box is " + box.width + "px wide" }
```

- An id is **not** a property and isn't a string. Write it without quotes.
- Ids are only visible **inside the file that declares them**.
- `parent` is a built-in reference to the enclosing visual object.
- By convention the root object gets `id: root`. Panel.qml does this.

---

## 5. Bindings: the key idea

This is what makes QML different from other UI code. When you write

```qml
text: "Clicked " + win.clicks + " times"
```

you aren't assigning a value once. You're writing an **expression that QML
re-evaluates whenever anything it reads changes**. When `win.clicks` changes, the
text updates automatically. That is a **property binding**.

```qml
import QtQuick

Window {
  id: win
  width: 320; height: 200; visible: true
  property int clicks: 0

  Rectangle {
    anchors.fill: parent
    // Recomputed whenever `clicks` changes.
    color: win.clicks % 2 === 0 ? "steelblue" : "tomato"

    Text {
      anchors.centerIn: parent
      color: "white"
      font.pixelSize: 20
      text: "Clicked " + win.clicks + " times"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: win.clicks++        // change the data; the UI follows
    }
  }
}
```

The click handler never touches the text or the colour. It only changes
`clicks`, and the bindings do the rest. A good rule:

> **Change state. Let bindings derive the UI from it.**

Panel.qml works this way. `finishTranslate()` only sets `root.busy`,
`root.resultText` and `root.errorText`. The result card's `text`, `opacity` and
`color` are bindings on those properties.

### Breaking a binding (common bug)

An **assignment in JavaScript replaces the binding** with a fixed value:

```qml
Text {
  id: label
  text: "Count: " + win.clicks       // binding
}
// somewhere in a handler:
label.text = "Reset!"                // binding is gone; clicks no longer updates it
```

If you really need to install a new binding from JS, use
`label.text = Qt.binding(function() { return "Count: " + win.clicks })`. Usually
the cleaner fix is to add a state property and bind to that.

---

## 6. Layout: positioning things

QML has no CSS box model. There are three main tools.

### a) `x`, `y`, `width`, `height`

These are absolute positions relative to the parent, and the simplest option.

### b) Anchors

Anchors tie an item's edges to another item's edges:

```qml
import QtQuick

Window {
  width: 400; height: 250; visible: true

  Rectangle {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 50
    color: "#334"
  }

  Rectangle {
    anchors.top: header.bottom       // stack under the header
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 10              // gap on every anchored side
    color: "#ddd"
  }
}
```

Shortcuts: `anchors.fill: parent`, `anchors.centerIn: parent`,
`anchors.verticalCenter: other.verticalCenter`. You can only anchor to your
**parent or siblings**.

### c) Positioners and Layouts

```qml
Column {                 // stacks children vertically (Row = horizontally)
  spacing: 8
  Rectangle { width: 100; height: 30; color: "red" }
  Rectangle { width: 100; height: 30; color: "green" }
}
```

`Row`, `Column`, `Grid` and `Flow` only *place* children. They don't resize them.
For stretching ("take the remaining width"), use the `QtQuick.Layouts` module:

```qml
import QtQuick.Layouts

RowLayout {
  width: 300
  Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 30; color: "red" }   // stretches
  Rectangle { Layout.preferredWidth: 60; Layout.preferredHeight: 30; color: "blue" }
}
```

Inside a Layout, size children with `Layout.*` properties, not `width`/`height`.
The layout owns those, and qmllint warns if you set them.

Panel.qml uses a `Column` and a `Row` and calculates widths by hand
(`(parent.width - swapButton.width - parent.spacing * 2) / 2`), which is the
same effect without the Layouts module.

### Implicit size

Many items know their natural size. A `Text`, for example, has `implicitWidth`
and `implicitHeight` from its content. Containers use it when you don't set
`width`/`height`. Panel.qml sizes the popup with `column.implicitHeight`.

---

## 7. Signals and handlers: events

Objects **emit signals** when something happens. You react with a **handler**
named `on` + the signal name with a capital first letter:

| Signal | Handler |
|---|---|
| `clicked` on a `MouseArea` / `Button` | `onClicked: …` |
| `pressed(event)` on `Keys` | `Keys.onPressed: function(event) { … }` |
| `triggered` on a `Timer` | `onTriggered: …` |

### Every property has a change signal

For each property `foo`, QML adds a `fooChanged` signal, so you can watch any
property:

```qml
property string query: ""
onQueryChanged: console.log("query is now", query)
```

### Your own signals

```qml
// Counter.qml
import QtQuick

Rectangle {
  signal reachedTen()
  property int value: 0
  onValueChanged: if (value === 10) reachedTen()
}
```

```qml
Counter { onReachedTen: console.log("ten!") }
```

### Handlers with arguments

Write the handler as a function to receive the arguments by name:

```qml
Keys.onPressed: function(event) {
  if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
}
```

`event.accepted = true` means "I handled it, don't pass it on". Panel.qml's text
box leaves Shift+Enter **unaccepted** so the `TextArea` underneath inserts a
newline.

### `Connections`: listening to an object you don't own

```qml
Connections {
  target: someOtherObject
  function onSomethingHappened() { … }
}
```

---

## 8. JavaScript in QML

You can write JS in three places:

```qml
Item {
  // 1. A function
  function fullName(first, last) { return first + " " + last }

  // 2. A binding expression
  property string who: fullName("Ada", "Lovelace")

  // 3. A handler body (one statement, or a { block })
  Component.onCompleted: {
    console.log("ready:", who)       // console.log prints to the terminal
  }
}
```

- `Component.onCompleted` runs once, after the object is built. It's QML's
  "on mount".
- QML JS is modern-ish ECMAScript (`let`, arrow functions, template strings all
  work), but there is **no DOM, no `fetch`, no `window`**.
- Keep logic small. Bindings should be cheap expressions. For heavy work, use C++,
  or do what this project does and run a separate process (the Ruby CLI).

---

## 9. Input

```qml
MouseArea {
  anchors.fill: parent
  hoverEnabled: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  cursorShape: Qt.PointingHandCursor
  onClicked: function(mouse) {
    if (mouse.button === Qt.RightButton) console.log("right click")
  }
  onEntered: console.log("hover")
}
```

- **`MouseArea`** is an invisible rectangle that catches the mouse. The bar pill
  uses qs.Ui's `BarIconButton`, whose `MouseArea` accepts left, right and middle
  clicks and passes the button to `onPressed`. BarWidget.qml then tells them apart.
- **`TapHandler`** / **`HoverHandler`** are the newer pointer handlers. They're
  lighter and compose better, and you can use them for new code.
- **Keyboard** events only reach the item with **`activeFocus`**. Call
  `item.forceActiveFocus()` to give it focus. Panel.qml does this to its input
  when the popup opens.

---

## 10. Reusable components

### A file is a type

`Badge.qml` defines a type called `Badge`, which any QML file **in the same
directory** can use without an import:

```qml
// Badge.qml
import QtQuick

Rectangle {
  id: root
  property alias label: txt.text      // expose an inner property
  property color tint: "slateblue"

  radius: height / 2
  color: tint
  implicitWidth: txt.implicitWidth + 16
  implicitHeight: txt.implicitHeight + 6

  Text { id: txt; anchors.centerIn: parent; color: "white" }
}
```

```qml
// main.qml (same folder)
import QtQuick

Window {
  width: 300; height: 100; visible: true
  Row {
    anchors.centerIn: parent
    spacing: 8
    Badge { label: "new" }
    Badge { label: "urgent"; tint: "crimson" }
  }
}
```

Points to notice:

- **Public API = root-level properties, signals and functions.** The `id`s
  inside stay private.
- **`property alias`** forwards to an inner object's property without copying
  it.
- Set **implicit** sizes in a component so the user of it can still override
  `width`/`height`.

This is what `qs.Ui` is: a folder of components such as `Dropdown`, `TextField`
and `PanelActionButton` that Panel.qml uses like built-in types.

### Inheriting

The root object of a file is its *base type*. qs.Ui's `TextField.qml` has
`TextField { … }` from Qt Quick Controls as its root, so it inherits all of that
type's API and adds theme styling on top.

### Creating objects on demand: `Component` + `Loader`

```qml
Loader {
  active: popupWanted               // create only when needed
  sourceComponent: Component {
    Rectangle { width: 200; height: 100; color: "gold" }
  }
}
```

`Loader` builds the object when `active` turns true and destroys it when it
turns false. BarWidget.qml loads Panel.qml this way. It is also why the shell
caches `Panel.qml`, which is the reason edits need `mise run reload`.

---

## 11. Lists: `Repeater`, `ListView` and models

A **model** is the data. A **delegate** is the template for each item.

```qml
import QtQuick

Window {
  width: 240; height: 220; visible: true

  ListView {
    anchors.fill: parent
    anchors.margins: 8
    spacing: 4
    model: ["Portuguese", "English", "German", "Japanese"]   // a JS array works
    delegate: Rectangle {
      id: row
      required property string modelData   // the current item
      required property int index
      width: ListView.view.width
      height: 36
      color: row.index % 2 ? "#eee" : "#ddd"
      Text { anchors.centerIn: parent; text: row.modelData }
    }
  }
}
```

- `model` can be a number (`model: 5`), a JS array, a `ListModel { ListElement {…} }`,
  or a C++ model.
- **`ListView`** scrolls and only creates the delegates that are visible.
- **`Repeater`** creates one delegate per item inside a `Row`/`Column`, with no
  scrolling. Use it for short lists.
- `required property` declares exactly which model roles the delegate uses. This
  is the modern style, and qmllint checks it.

---

## 12. States and animation

### Animate a property whenever it changes

```qml
Rectangle {
  width: 100; height: 100; color: "teal"
  opacity: hovered.hovered ? 1 : 0.4
  Behavior on opacity { NumberAnimation { duration: 150 } }   // smooth instead of instant

  HoverHandler { id: hovered }
}
```

`Behavior on X` makes any change to `X` animate. This is the easiest animation
to start with.

### Named states

```qml
Rectangle {
  id: panel
  width: 200; height: 40
  state: expanded ? "open" : ""
  property bool expanded: false

  states: State {
    name: "open"
    PropertyChanges { panel.height: 200 }
  }
  transitions: Transition { NumberAnimation { properties: "height"; duration: 200 } }
}
```

---

## 13. Qt Quick Controls: ready-made widgets

`import QtQuick.Controls` adds `Button`, `TextField`, `TextArea`, `CheckBox`,
`ComboBox`, `ScrollView`, `Slider` and more:

```qml
import QtQuick
import QtQuick.Controls

Window {
  width: 320; height: 240; visible: true

  Column {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    TextField { id: name; width: parent.width; placeholderText: "Your name" }

    ScrollView {                       // gives the TextArea a scrollbar
      width: parent.width
      height: 100
      TextArea { id: notes; placeholderText: "Multi-line notes…"; wrapMode: TextArea.Wrap }
    }

    Button {
      text: "Greet"
      enabled: name.text.length > 0    // binding: disabled while empty
      onClicked: console.log("Hello", name.text, "-", notes.text.length, "chars of notes")
    }
  }
}
```

Every control has a `background` (and often a `contentItem`) that you can
replace. That's how the Translator's text box gets Omarchy's theme: it sets
`background: BorderSurface { … }` with colours from `qs.Commons`.

---

## 14. Imports and modules

```qml
import QtQuick                 // core visual types
import QtQuick.Controls        // widgets
import QtQuick.Layouts         // RowLayout, ColumnLayout, GridLayout
import Quickshell              // Quickshell: PanelWindow, execDetached…
import Quickshell.Io           // Process, StdioCollector, FileView
import qs.Commons              // Omarchy: Style, Color (theme tokens)
import qs.Ui                   // Omarchy: shared components
import "components"            // a local folder of .qml files
import "utils.js" as Utils     // a JavaScript file as a namespace
```

`qs` is the root of the running Quickshell config, which here is Omarchy's shell.
That's why `qs.*` imports only resolve inside `omarchy-shell` and not under plain
`qml6`. Run the examples in this guide with `qml6`, and run the widget itself
through the shell.

---

## 15. Common mistakes

| Symptom | Likely cause |
|---|---|
| A value stopped updating | A JS assignment replaced a binding (§5) |
| Keys do nothing | The item doesn't have `activeFocus` (§9) |
| `ReferenceError: foo is not defined` | Unqualified name. Write `root.foo` rather than `foo` from deep inside children |
| Item has size 0 / invisible | No `width`/`height`/anchors and no implicit size |
| `Cannot anchor to an item that isn't a parent or sibling` | Anchors only work with your parent or siblings |
| `{a: 1}` behaves strangely | You need `({a: 1})` for an object literal |
| Edits don't show up in Omarchy | Loader cache. Run `mise run reload` |

**Qualify your names.** Writing `root.busy` instead of plain `busy` makes it
clear where the value comes from, makes bindings faster, and lets `qmllint` check
it. This project's lint gate fails on `[unqualified]` for that reason.

---

## 16. Where to see it in this repo

| Concept | Where |
|---|---|
| Custom properties as UI state | `Panel.qml`: `busy`, `resultText`, `errorText`, `copied` |
| Bindings driving the UI | `Panel.qml`: result card `text:` / `color:` / `opacity:` |
| Key handling, `event.accepted` | `Panel.qml`: `inputField`'s `Keys.onPressed` |
| A control with a custom `background` | `Panel.qml`: the `ScrollView` + `TextArea` input |
| Running a subprocess | `Panel.qml`: `Process` + `StdioCollector` |
| `Timer` | `Panel.qml`: `watchdog`, `copiedTimer` |
| Telling mouse buttons apart | `BarWidget.qml`: `BarIconButton`'s `onPressed` |
| `Loader` | `BarWidget.qml` loading `Panel.qml` |
| `ListView` + `Popup`, delegates with `required property` | `ProviderDropdown.qml`: the provider list |
| A component of your own, used like a built-in type | `ProviderDropdown.qml` and `ProviderLogo.qml`, used in `Panel.qml` |
| A non-visual object holding functions | `PanelLogic.qml` (a `QtObject`), declared in `Panel.qml` as `logic` |
| Testing QML with `TestCase` | `test/qml/`: `tst_panel_logic.qml`, `tst_panel.qml`, `tst_bar_widget.qml` |
| Reusable themed components | `/usr/share/omarchy/shell/Ui/*.qml` |

---

## 17. Exercises

1. **Counter+:** add a "Reset" button to the §5 example without breaking any
   binding.
2. **Badge list:** use a `Repeater` with `model: ["a", "b", "c"]` to show three
   `Badge`s from §10.
3. **Live preview:** a `TextField` plus a `Text` that shows the typed text
   uppercased and its length. It should be pure bindings, with no handlers.
4. **Fade on hover:** make the §11 list rows highlight on hover with
   `HoverHandler` and `Behavior on color`.
5. **Read the real thing:** open `Panel.qml` and trace what happens, property by
   property, from pressing Enter to the result appearing. Check your answer
   against the sequence diagram in [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

---

## Further reading

- [Qt docs: QML Applications](https://doc.qt.io/qt-6/qmlapplications.html): the
  official starting point
- [The QML Book](https://www.qt.io/product/qt6/qml-book): a free, thorough book
- [Qt Quick types index](https://doc.qt.io/qt-6/qtquick-qmlmodule.html)
- [Qt Quick Controls](https://doc.qt.io/qt-6/qtquickcontrols-index.html)
- [Quickshell docs](https://quickshell.org/docs/): `Process`, `PanelWindow`
  and the other shell-specific types
