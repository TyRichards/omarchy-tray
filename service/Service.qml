import QtQuick

// Service entry point for the tray plugin.
//
// The shell hands third-party bar widgets a PluginBarApi facade that carries
// no widget registry, but it still injects the bar widget catalogue into a
// plugin's service entry point. This object exists to receive that
// catalogue. Tray.qml reads it back through bar.shell.serviceFor(<own id>)
// and instantiates the captured widgets from it.
//
// It lives in its own directory because the QML loader caches a directory
// listing. A file added later to a directory the loader has already read
// fails with "File name case mismatch" until the shell restarts, which is
// what happened while this was a sibling of Tray.qml. A fresh directory has
// no cached listing, so a new install loads it straight away. An upgrade in
// place is not proven to, so the README asks for one shell restart.
QtObject {
  // Injected by the shell. Nothing else here reads it; Tray.qml does.
  property var barWidgetRegistry: null
}
