import QtQuick
import qs
import qs.components

Lb {
    px: 11.5
    font.bold: true
    readonly property color foreground: Theme.light ? "black" : "white"
    color: foreground
}
