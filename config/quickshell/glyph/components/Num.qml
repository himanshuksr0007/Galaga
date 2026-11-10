import QtQuick
import qs

// digits and short words: Doto, round dots (ROND 100). Not smaller than 26px.
// Frame -- like line-height .85 in the concept: lineHeight does not work for a single-line Text, so negative margins
// (Doto line 1.2em -> .85em). Your own padding -- `topPadding: lead + 8`
Text {
    textFormat: Text.PlainText
    readonly property real lead: -0.175 * font.pixelSize
    font { family: Theme.dot; pixelSize: 44; weight: Font.Black; variableAxes: ({ "ROND": 100, "wght": 900 }) }
    topPadding: lead
    bottomPadding: lead
    color: Theme.fg
}
