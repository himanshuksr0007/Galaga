import QtQuick
import qs

// 1920x1080 layout canvas in pixels: stretched to the parent, everything inside is measured as in concept.html
Item {
    width: parent.width / Theme.s
    height: parent.height / Theme.s
    scale: Theme.s
    transformOrigin: Item.TopLeft
}
