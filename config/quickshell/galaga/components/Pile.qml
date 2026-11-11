import QtQuick
import qs

// the bar: a column at the left edge, a row on top (Theme.state.barAt); centered across. Only columns -- Grid
// computes rows itself, otherwise on an edge switch columns and rows change one after the other and for a moment
// it is 1x1 ("more visible items than rows*columns" in the log).
// Its own file, not an inline component: a new inline component breaks hot reload ("is not a type") until qs restarts
Grid {
    readonly property bool vert: Theme.state.barAt !== "top"
    columns: vert ? 1 : 99
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
