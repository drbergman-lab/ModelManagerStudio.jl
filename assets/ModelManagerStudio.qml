import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts
import jlqml

ApplicationWindow {
    id: mainWindow

    property var fontSizeOfLevel: [20, 18, 14, 12, 10]

    // The highlight applied to an input location whose folder supports parameter variation.
    // Defined once so the legend swatch and the location tiles cannot drift apart.
    property color variedHighlight: "#cfe6ff"
    property string variedMarker: "\u25C8"   // ◈ — a non-color cue, since color alone fails WCAG 1.4.1

    // An optional location with no folder chosen. It gets a filled tile of the SAME geometry
    // as a varied one, so the grid reads as a set of equal cells in three states rather than
    // some tiles having a box and others floating with no boundary at all.
    property color unusedTint: "#d2d7dd"
    property color unusedTextColor: "#767d86"

    // The page sits a shade darker than an in-use tile and a shade lighter than an unused one,
    // so the three tile states read as three states rather than as one flat field.
    property color pageBackground: "#e4e8ed"
    property color tileBackground: "#ffffff"

    // An enabled button is white with a dark edge; a disabled one is flat and grey. Qt's Basic
    // style gives both the same grey, which on this page reads as "disabled" throughout.
    property color buttonBackground: "#ffffff"
    property color buttonBorder: "#8d97a3"
    property color buttonPressed: "#d9e4f0"
    property color buttonHovered: "#f2f6fb"
    property color buttonDisabledBackground: "#dde1e6"
    property color buttonDisabledBorder: "#c4c9cf"
    property color buttonDisabledText: "#949aa2"

    component ActionButton: Button {
        id: actionButton

        background: Rectangle {
            radius: 4
            color: !actionButton.enabled ? mainWindow.buttonDisabledBackground
                 : actionButton.down ? mainWindow.buttonPressed
                 : actionButton.hovered ? mainWindow.buttonHovered
                 : mainWindow.buttonBackground
            border.width: 1
            border.color: actionButton.enabled ? mainWindow.buttonBorder
                                               : mainWindow.buttonDisabledBorder
        }

        contentItem: Text {
            text: actionButton.text
            font: actionButton.font
            color: actionButton.enabled ? syscolors.text : mainWindow.buttonDisabledText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    // Colour for a token the backend says nothing about -- for PhysiCell, its own schema,
    // which is most of the document. The backend supplies a hex for the rest, one hue per
    // category of name it recognises, so a category reads the same wherever it turns up.
    property color defaultTokenColor: "#000000"

    // Breathing room added to a ComboBox on top of its own padding and indicator width.
    // The token chain measures its widest entry with a hidden Text and sizes to that, but a
    // Text's implicitWidth is the glyph run alone -- it accounts for neither the control's
    // padding nor the drop-down indicator, so entries clipped ("apoptosis" -> "apoptosi").
    property int comboTextSlack: 14

    title: "ModelManagerStudio"
    width: 800
    height: 600
    // Below this the location grids reflow into something unreadable, and the run bar starts
    // eating the panel above it. The Inputs tab scrolls past this point rather than clipping.
    minimumWidth: 560
    minimumHeight: 360
    visible: true

    // Add keyboard shortcut for Command+W to close the window
    Shortcut {
        sequences: [StandardKey.Close] // This maps to Cmd+W on macOS
        onActivated: mainWindow.close()
    }

    SystemPalette {
        id: syscolors

        colorGroup: SystemPalette.Active
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        anchors.margins: 10

        // Simulated tab bar
        Rectangle {
            color: guiproperties.color_top
            Layout.fillWidth: true
            Layout.preferredHeight: 40

            RowLayout {
                id: tabBar

                property int currentIndex: 0 // Track the currently selected tab index

                spacing: 0
                anchors.centerIn: parent

                Component {
                    id: tabButtonComponent

                    RoundButton {
                        id: button

                        property int index: -1 // Allow access to the index of the tab

                        text: "test"
                        font.bold: true
                        font.underline: index === tabBar.currentIndex // Underline the current tab
                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                        onClicked: {
                            tabBar.currentIndex = index; // Update the current index when clicked
                        }

                        background: Rectangle {
                            id: background

                            color: index === tabBar.currentIndex ? guiproperties.color_button : "#ffffff" // Change color based on current index
                            implicitWidth: 100
                            implicitHeight: 25
                            border.width: 2
                            border.color: index === tabBar.currentIndex ? "#000000" : "#a0a0a0" // Darker border for selected tab
                            radius: 4
                        }

                    }

                }

                Repeater {
                    model: ["Inputs", "Variations"]

                    delegate: Loader {
                        id: tabLoader

                        onLoaded: {
                            item.text = modelData; // Set the text based on the model data
                            item.index = index; // Set the index for the tab
                        }
                        sourceComponent: tabButtonComponent
                    }

                }

            }

        }

        // Content area
        StackLayout {
            id: stack

            currentIndex: tabBar.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Inputs tab
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: mainWindow.pageBackground

                // The tab's content has a fixed minimum height -- two location grids, a
                // button and the inputs panel -- so below a certain window height it has to
                // scroll. Without this it was clipped by the run bar, and "Current Inputs"
                // was the part that went.
                ScrollView {
                    id: inputsScrollView

                    anchors.fill: parent
                    contentWidth: availableWidth // vertical scrolling only
                    clip: true

                ColumnLayout {
                    // Anchoring a ScrollView's content item is an error; bind the width instead.
                    width: inputsScrollView.availableWidth
                    spacing: 10 // Reduced spacing for more compact vertical layout

                    Component {
                        id: locationComponent

                        Item {
                            // Use Item as the root to properly handle layout
                            id: locationItem

                            property int level: 2 // level of the item, used for font size
                            property string labelText: "Default Text"
                            property string location: "default_location"
                            property bool isVaried: false
                            property bool isRequired: false
                            // Declarative rather than assigned in a handler, so it cannot fall
                            // out of step with what the ComboBox is actually showing.
                            property bool isUnused: !isRequired
                                && (locationComboBox.currentText === project_configuration_properties.no_folder_sentinel
                                    || locationComboBox.currentText === "")
                            property alias comboBox: locationComboBox
                            property alias label: labelTextItem // These layout properties will be applied when used in a Layout

                            signal comboChanged(string newText)

                            Layout.alignment: Qt.AlignCenter
                            width: rect.width
                            height: rect.height

                            // The actual rectangle with background color
                            Rectangle {
                                id: rect

                                width: columnLayout.implicitWidth + 10
                                height: columnLayout.implicitHeight + 10 // padding/margin
                                color: locationItem.isVaried ? mainWindow.variedHighlight
                                     : locationItem.isUnused ? mainWindow.unusedTint
                                     : mainWindow.tileBackground
                                radius: 4
                                border.width: 1
                                border.color: Qt.darker(color, 1.25)

                                ColumnLayout {
                                    id: columnLayout

                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        id: labelTextItem

                                        text: locationItem.isVaried ? (mainWindow.variedMarker + " " + labelText) : labelText
                                        font.bold: true
                                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                                        color: locationItem.isUnused ? mainWindow.unusedTextColor : syscolors.text
                                        Accessible.role: Accessible.StaticText
                                        Accessible.name: locationItem.isVaried
                                            ? (labelText + ", supports parameter variation")
                                            : locationItem.isUnused ? (labelText + ", not in use")
                                            : labelText
                                    }

                                    // ComboBox for selecting folder locations
                                    ComboBox {
                                        id: locationComboBox

                                        // Function to update folders when location or variation state changes
                                        function updateFolders() {
                                            model = Julia.get_folders(locationItem.location, locationItem.isRequired);
                                        }

                                        onCurrentTextChanged: {
                                            // Update the varied state when the current text changes
                                            locationItem.isVaried = Julia.is_varied_location(locationItem.location, locationItem.comboBox.currentText);
                                            locationItem.comboChanged(currentText);
                                        }
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.preferredWidth: 180
                                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                                    }

                                }

                            }

                        }

                    }

                    // Required Locations
                    Text {
                        text: "Required Locations"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        font.underline: true
                        Layout.alignment: Qt.AlignCenter
                    }

                    GridLayout {
                        id: reqGridLayout

                        Layout.alignment: Qt.AlignCenter
                        rows: project_configuration_properties.req_n_rows
                        columns: project_configuration_properties.req_n_cols
                        flow: GridLayout.TopToBottom

                        Repeater {
                            id: requiredLocationsRepeater

                            model: reqLocModel

                            delegate: Loader {
                                id: requiredLocationLoader

                                sourceComponent: locationComponent
                                onLoaded: {
                                    item.labelText = labelText;
                                    item.location = location; // Convert to a suitable location name
                                    item.isVaried = false; // Set varied state
                                    item.isRequired = true; // Set required state
                                    item.comboChanged.connect(function(newText) {
                                        folder = newText; // Update the folder variable
                                    });
                                    item.comboBox.updateFolders(); // Update folders in the combo box
                                }
                            }

                        }

                    }

                    // Optional Locations
                    Text {
                        Layout.alignment: Qt.AlignCenter
                        text: "Optional Locations"
                        color: syscolors.text
                        font.bold: true
                        font.underline: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                    }

                    GridLayout {
                        id: optGridLayout

                        Layout.alignment: Qt.AlignCenter
                        rows: project_configuration_properties.opt_n_rows
                        columns: project_configuration_properties.opt_n_cols
                        flow: GridLayout.TopToBottom

                        Repeater {
                            id: optionalLocationsRepeater

                            model: optLocModel

                            delegate: Loader {
                                id: optionalLocationLoader

                                sourceComponent: locationComponent
                                onLoaded: {
                                    item.labelText = labelText;
                                    item.location = location; // Convert to a suitable location name
                                    item.isVaried = false; // Set varied state
                                    item.isRequired = false; // Set required state
                                    item.comboChanged.connect(function(newText) {
                                        folder = newText; // Update the folder variable
                                    });
                                    item.comboBox.updateFolders(); // Update folders in the combo box
                                }
                            }

                        }

                    }


                    // Legend. Bottom right and muted: centred under the tab bar it read as a
                    // row of buttons, which is the one thing it must not look like.
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        Layout.rightMargin: 16
                        Layout.topMargin: 2
                        spacing: 5

                        // The swatch carries the glyph, so it is a miniature of an actual
                        // varied tile rather than two separate cues sitting next to a
                        // sentence that has to explain both.
                        Rectangle {
                            width: legendGlyph.implicitWidth + 6
                            height: legendGlyph.implicitHeight + 2
                            radius: 2
                            color: mainWindow.variedHighlight
                            border.width: 1
                            border.color: Qt.darker(mainWindow.variedHighlight, 1.25)
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: legendGlyph

                                anchors.centerIn: parent
                                text: mainWindow.variedMarker
                                color: mainWindow.unusedTextColor
                                font.pixelSize: mainWindow.fontSizeOfLevel[4]
                            }
                        }

                        Text {
                            text: "can be varied"
                            color: mainWindow.unusedTextColor
                            font.pixelSize: mainWindow.fontSizeOfLevel[4]
                            Layout.alignment: Qt.AlignVCenter
                            rightPadding: 10
                        }

                        Rectangle {
                            width: legendGlyph.implicitWidth + 6
                            height: legendGlyph.implicitHeight + 2
                            radius: 2
                            color: mainWindow.unusedTint
                            border.width: 1
                            border.color: Qt.darker(mainWindow.unusedTint, 1.25)
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: "not in use"
                            color: mainWindow.unusedTextColor
                            font.pixelSize: mainWindow.fontSizeOfLevel[4]
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // Button to create inputs
                    ActionButton {
                        Layout.alignment: Qt.AlignCenter
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 40
                        text: "Create Inputs"
                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                        onClicked: {
                            // Set input folders in Julia
                            Julia.set_input_folders();
                            // Update the display to show current selections
                            requiredLocationsDisplay.updateFolderDisplay();
                            optionalLocationsDisplay.updateFolderDisplay();
                            // Hide the placeholder text and show the inputs display
                            inputsPlaceholderText.visible = false;
                            inputsDisplay.visible = true;
                            variedLocationComboBox.model = Julia.get_varied_locations();
                            // Julia dropped the hits behind these rows when the folders
                            // changed, so a list left on screen is rows that apply to nothing.
                            parameterSearchRow.clearSearch();
                            currentVariationTargetText.updateVariationTarget(); // Update the target text
                            if (runSimulationButton.enabled === false) {
                                runSimulationButton.enabled = true; // Enable the run simulation button
                                runSimulationButton.disabledText = "Running...";
                            }
                        }
                    }

                    // Current inputs display
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.leftMargin: 50
                        Layout.rightMargin: 50

                        Text {
                            text: "Current Inputs"
                            font.bold: true
                            font.pixelSize: mainWindow.fontSizeOfLevel[1]
                            color: syscolors.text
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            // Layout.fillHeight: true
                            implicitHeight: inputsDisplay.implicitHeight + 20
                            color: "#fafafa"
                            radius: 6
                            border.color: "#a0a0a0"
                            border.width: 2

                            Text {
                                id: inputsPlaceholderText

                                anchors.centerIn: parent
                                text: "Inputs will be displayed here after creation"
                                horizontalAlignment: Text.AlignHCenter
                                font.italic: true
                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                color: "#888888"
                                visible: true
                            }

                            RowLayout {
                                id: inputsDisplay

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                anchors.fill: parent
                                spacing: 10
                                visible: false // Initially hidden, will be shown when inputs are created

                                // Display required locations
                                ColumnLayout {
                                    id: requiredLocationsDisplay

                                    // Function to update the text values with current selections
                                    function updateFolderDisplay() {
                                        // The Repeater will handle displaying each item
                                        let temp_mod = [];
                                        for (let i = 0; i < requiredLocationsRepeater.count; ++i) {
                                            let item = requiredLocationsRepeater.itemAt(i).item;
                                            temp_mod.push({
                                                "name": item.labelText,
                                                "value": Julia.get_input_folder(item.location)
                                            });
                                        }
                                        requiredFoldersRepeater.model = temp_mod;
                                    }

                                    Layout.alignment: Qt.AlignTop
                                    Layout.margins: 5

                                    Text {
                                        text: "Required Locations"
                                        color: syscolors.text
                                        font.bold: true
                                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                    }

                                    Repeater {
                                        id: requiredFoldersRepeater

                                        RowLayout {
                                            Layout.leftMargin: 20
                                            spacing: 5

                                            Text {
                                                text: modelData.name + ":"
                                                color: syscolors.text
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                horizontalAlignment: Text.AlignRight
                                                width: 120 // Fixed width for alignment
                                            }

                                            Text {
                                                text: modelData.value
                                                color: syscolors.text
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                horizontalAlignment: Text.AlignLeft
                                            }

                                        }

                                    }

                                }

                                // Display optional locations
                                ColumnLayout {
                                    id: optionalLocationsDisplay

                                    // This function will force the repeater to reevaluate its values
                                    function updateFolderDisplay() {
                                        let temp_mod = [];
                                        for (let i = 0; i < optionalLocationsRepeater.count; ++i) {
                                            let item = optionalLocationsRepeater.itemAt(i).item;
                                            temp_mod.push({
                                                "name": item.labelText,
                                                "value": Julia.get_input_folder(item.location)
                                            });
                                        }
                                        optionalFoldersRepeater.model = temp_mod;
                                    }

                                    Layout.alignment: Qt.AlignTop
                                    Layout.margins: 5

                                    Text {
                                        text: "Optional Locations"
                                        color: syscolors.text
                                        font.bold: true
                                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                    }

                                    // Use a Repeater to generate optional folder displays
                                    Repeater {
                                        id: optionalFoldersRepeater

                                        RowLayout {
                                            Layout.leftMargin: 20
                                            spacing: 5
                                            visible: modelData.value !== project_configuration_properties.no_folder_sentinel

                                            Text {
                                                text: modelData.name + ":"
                                                color: syscolors.text
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                horizontalAlignment: Text.AlignRight
                                                Layout.preferredWidth: 120 // Fixed width for alignment
                                            }

                                            Text {
                                                text: modelData.value
                                                color: syscolors.text
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                horizontalAlignment: Text.AlignLeft
                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                }

                }
            }

            // Variations tab
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: mainWindow.pageBackground

                ColumnLayout {
                    spacing: 10 // Reduced spacing for more compact vertical layout
                    anchors.centerIn: parent
                    anchors.fill: parent

                    Text {
                        text: "Variation target"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        Layout.alignment: Qt.AlignLeft
                        Layout.leftMargin: 0
                    }

                    // Variation target box
                    Rectangle {
                        property int padding: 12

                        Layout.alignment: Qt.AlignCenter
                        Layout.fillWidth: true
                        color: "#fafafa"
                        radius: 6
                        border.color: "#a0a0a0"
                        border.width: 2
                        implicitHeight: variationTargetColumnLayout.implicitHeight + 2 * padding

                        ColumnLayout {
                            id: variationTargetColumnLayout

                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: parent.padding

                            // Jump straight to a parameter by name, across every location
                            // that supports variation. The walk below produces honest but deep
                            // paths; this is how you get to the bottom of one without clicking
                            // through every level of it.
                            RowLayout {
                                id: parameterSearchRow

                                Layout.fillWidth: true
                                spacing: 8

                                // Drives the location dropdown and then each token ComboBox in
                                // turn, so a jump lands on exactly the state a hand-walked chain
                                // would have produced.
                                function applyResult(row) {
                                    let toks = Julia.search_result_tokens(row);
                                    if (toks.length < 2)
                                        return ;

                                    let locationIndex = -1;
                                    for (let k = 0; k < variedLocationComboBox.model.length; ++k) {
                                        if (variedLocationComboBox.model[k] === toks[0]) {
                                            locationIndex = k;
                                            break;
                                        }
                                    }
                                    if (locationIndex < 0)
                                        return ;

                                    variedLocationComboBox.currentIndex = locationIndex;
                                    // Assigning an unchanged currentIndex emits nothing, so the
                                    // cascade cannot be relied on to have run. Seed the first
                                    // level, then force each next one after setting its parent.
                                    tokenComboBoxRepeater.itemAt(0).model = Julia.get_next_model(toks[0]);
                                    for (let d = 1; d < toks.length; ++d) {
                                        let combo = tokenComboBoxRepeater.itemAt(d - 1);
                                        let tokenIndex = -1;
                                        for (let k = 0; k < combo.model.length; ++k) {
                                            if (combo.model[k] === toks[d]) {
                                                tokenIndex = k;
                                                break;
                                            }
                                        }
                                        if (tokenIndex < 0)
                                            return ;

                                        combo.currentIndex = tokenIndex;
                                        combo.updateNextComboBox();
                                    }
                                    // The parameter itself is the rightmost box, which is
                                    // off-screen for any chain wider than the window -- so a
                                    // jump that does not scroll lands out of sight.
                                    Qt.callLater(parameterSearchRow.revealChainEnd);
                                    // Deferred: this runs from the clicked delegate's own
                                    // handler, and clearing the field empties the list model
                                    // that delegate belongs to.
                                    Qt.callLater(parameterSearchRow.clearSearch);
                                }

                                function clearSearch() {
                                    searchResultsPopup.close();
                                    parameterSearchField.text = "";
                                }

                                function revealChainEnd() {
                                    let overflow = comboFlickable.contentWidth - comboFlickable.width;
                                    comboFlickable.contentX = overflow > 0 ? overflow : 0;
                                }

                                TextField {
                                    id: parameterSearchField

                                    Layout.fillWidth: true
                                    placeholderText: "Find a parameter\u2026  e.g. \"bacteria speed\""
                                    font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                    selectByMouse: true

                                    function runSearch() {
                                        if (text === "") {
                                            searchResultsPopup.close();
                                            searchResultsList.model = [];
                                            return ;
                                        }
                                        searchResultsList.model = Julia.search_parameters(text);
                                        searchResultsPopup.total = Julia.search_result_count();
                                        searchResultsList.currentIndex = 0;
                                        // Name the locations actually searched when nothing
                                        // matched. An unselected folder is the usual reason a
                                        // parameter cannot be found, and it is otherwise
                                        // invisible: the location is simply missing from a list
                                        // the user never sees.
                                        searchResultsPopup.scope = searchResultsList.model.length > 0
                                            ? "" : Julia.search_scope().join(", ");
                                        searchResultsPopup.open();
                                    }

                                    onTextChanged: runSearch()
                                    // The popup never takes focus, so the keys that move through
                                    // it and pick from it are handled here.
                                    Keys.onDownPressed: {
                                        if (searchResultsList.currentIndex < searchResultsList.model.length - 1)
                                            searchResultsList.currentIndex += 1;

                                    }
                                    Keys.onUpPressed: {
                                        if (searchResultsList.currentIndex > 0)
                                            searchResultsList.currentIndex -= 1;

                                    }
                                    Keys.onReturnPressed: {
                                        if (searchResultsList.model.length > 0)
                                            parameterSearchRow.applyResult(searchResultsList.currentIndex);

                                    }
                                    Keys.onEscapePressed: searchResultsPopup.close()

                                    Popup {
                                        id: searchResultsPopup

                                        // Matches before the display cap, so a list that was
                                        // truncated says so instead of looking complete.
                                        property int total: 0
                                        // Locations searched, listed only when nothing matched.
                                        property string scope: ""

                                        y: parameterSearchField.height
                                        width: parameterSearchField.width
                                        padding: 1
                                        // The popup never takes focus, so the caret stays in the
                                        // field and the arrow keys keep reaching it. It still has
                                        // to be dismissable by clicking away, or a list left open
                                        // covers the browser underneath it.
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                        // Dismissing has to disarm the keys too. The Return
                                        // handler fires on whatever the list still holds, so a
                                        // list left populated behind a closed popup would let
                                        // Return rewrite the whole chain from an invisible
                                        // selection.
                                        onClosed: searchResultsList.model = []

                                        contentItem: ColumnLayout {
                                            spacing: 0

                                            ListView {
                                                id: searchResultsList

                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Math.min(contentHeight, 320)
                                                clip: true
                                                model: []
                                                boundsBehavior: Flickable.StopAtBounds

                                                delegate: ItemDelegate {
                                                    width: ListView.view ? ListView.view.width : implicitWidth
                                                    highlighted: ListView.isCurrentItem
                                                    onClicked: parameterSearchRow.applyResult(index)

                                                    contentItem: Text {
                                                        text: modelData
                                                        color: syscolors.text
                                                        font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                        elide: Text.ElideLeft
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                }

                                                ScrollIndicator.vertical: ScrollIndicator {
                                                }

                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.margins: 6
                                                visible: searchResultsList.model.length === 0
                                                wrapMode: Text.Wrap
                                                text: searchResultsPopup.scope === ""
                                                    ? "No match. No location has a folder to search \u2014 create inputs first."
                                                    : "No match in " + searchResultsPopup.scope + ". A location with no folder chosen is not searched."
                                                color: mainWindow.unusedTextColor
                                                font.pixelSize: mainWindow.fontSizeOfLevel[4]
                                                font.italic: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.margins: 6
                                                visible: searchResultsPopup.total > searchResultsList.model.length && searchResultsList.model.length > 0
                                                text: "Showing " + searchResultsList.model.length + " of " + searchResultsPopup.total + " \u2014 narrow the search"
                                                color: mainWindow.unusedTextColor
                                                font.pixelSize: mainWindow.fontSizeOfLevel[4]
                                                font.italic: true
                                            }

                                        }

                                    }

                                }

                            }

                            RowLayout {
                                id: variationRowLayout

                                Layout.fillWidth: true
                                Layout.preferredHeight: comboRow.implicitHeight + 20 // Add some padding
                                Layout.alignment: Qt.AlignTop

                                // Plain delegate for the location ComboBox. The token
                                // ComboBoxes have their own, which adds the branch marker.
                                Component {
                                    id: coloredItemDelegate

                                    ItemDelegate {
                                        property int level: 2

                                        contentItem: Text {
                                            text: modelData
                                            color: "#000000"
                                            font.pixelSize: mainWindow.fontSizeOfLevel[level]
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                Flickable {
                                    id: comboFlickable

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    contentWidth: comboRow.implicitWidth
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    Row {
                                        id: comboRow

                                        spacing: 5

                                        ComboBox {
                                            id: variedLocationComboBox

                                            property int longestTextWidth: 0

                                            function updateLongestTextWidth() {
                                                if (model === undefined) {
                                                    longestTextWidth = 0;
                                                    return ;
                                                }
                                                let longest = "";
                                                for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                                    longest = model[i];
                                                }
                                                dummyTextItemLocation.text = longest;
                                                longestTextWidth = dummyTextItemLocation.implicitWidth;
                                            }

                                            width: longestTextWidth + leftPadding + rightPadding
                                                   + (indicator ? indicator.width : 0)
                                                   + mainWindow.comboTextSlack
                                            model: []
                                            // Use the colored delegate
                                            delegate: coloredItemDelegate
                                            onModelChanged: updateLongestTextWidth()
                                            onCurrentTextChanged: {
                                                // Update the token combo boxes based on the selected location
                                                // Prevent updates while changing location
                                                tokenComboBoxRepeater.itemAt(0).model = Julia.get_next_model(variedLocationComboBox.currentText);
                                                tokenComboBoxRepeater.itemAt(0).modelChanged(); // Force update in case the model is the same
                                            }

                                            Text {
                                                id: dummyTextItemLocation

                                                visible: false
                                                font: variedLocationComboBox.font
                                            }

                                        }

                                        Repeater {
                                            id: tokenComboBoxRepeater

                                            model: 100

                                            delegate: ComboBox {
                                                id: tokenComboBox

                                                property int longestTextWidth: 0
                                                // Branch/leaf and colour per entry, index-parallel to `model`.
                                                property var itemKinds: []
                                                property var itemColors: []

                                                // Search-within-a-level. The walk produces honest but deep
                                                // paths, so a level can hold many siblings; typing narrows
                                                // them. Filtering hides delegates rather than replacing
                                                // `model`, deliberately: mutating the model would reset
                                                // currentIndex on every keystroke and re-fire the cascade
                                                // that rebuilds every ComboBox to the right.
                                                property string filterText: ""

                                                function matchesFilter(token) {
                                                    if (filterText === "")
                                                        return true;

                                                    return token.toString().toLowerCase().indexOf(filterText.toLowerCase()) !== -1;
                                                }

                                                function visibleCount() {
                                                    if (model === undefined)
                                                        return 0;

                                                    let n = 0;
                                                    for (let i = 0; i < model.length; ++i) if (matchesFilter(model[i]))
                                                        ++n;
                                                    return n;
                                                }

                                                // The chain UP TO this ComboBox is what produced its model, so
                                                // the same chain yields this level's headings and kinds.
                                                function refreshMeta() {
                                                    var toks = [variedLocationComboBox.currentText];
                                                    for (let i = 0; i < index; ++i) {
                                                        toks.push(tokenComboBoxRepeater.itemAt(i).currentText);
                                                    }
                                                    itemKinds = Julia.get_token_kinds.apply(Julia, toks);
                                                    itemColors = Julia.get_token_colors.apply(Julia, toks);
                                                }

                                                function updateLongestTextWidth() {
                                                    let longest = "";
                                                    for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                                        longest = model[i];
                                                    }
                                                    dummyTextItem.text = longest;
                                                    longestTextWidth = dummyTextItem.implicitWidth;
                                                }

                                                function updateNextComboBox() {
                                                    var tokens = [variedLocationComboBox.currentText];
                                                    for (let i = 0; i <= index; ++i) {
                                                        tokens.push(tokenComboBoxRepeater.itemAt(i).currentText);
                                                    }
                                                    let next_model = Julia.get_next_model.apply(Julia, tokens);
                                                    if (next_model !== undefined && next_model.length > 0) {
                                                        tokenComboBoxRepeater.itemAt(index + 1).model = next_model;
                                                    } else {
                                                        for (let i = index + 1; i < tokenComboBoxRepeater.count; ++i) {
                                                            tokenComboBoxRepeater.itemAt(i).model = [];
                                                        }
                                                        currentVariationTargetText.allowUpdates = true; // Allow updates to the target text
                                                        currentVariationTargetText.updateVariationTarget();
                                                    }
                                                }

                                                font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                                // The closed box shows the same hue as the row that was
                                                // picked, so a chain stays readable once it is built --
                                                // not only while a menu happens to be open.
                                                contentItem: Text {
                                                    text: tokenComboBox.displayText
                                                    font: tokenComboBox.font
                                                    color: {
                                                        let i = tokenComboBox.currentIndex;
                                                        if (i >= 0 && i < tokenComboBox.itemColors.length && tokenComboBox.itemColors[i] !== "")
                                                            return tokenComboBox.itemColors[i];

                                                        return mainWindow.defaultTokenColor;
                                                    }
                                                    verticalAlignment: Text.AlignVCenter
                                                    elide: Text.ElideRight
                                                }
                                                width: longestTextWidth + leftPadding + rightPadding
                                                       + (indicator ? indicator.width : 0)
                                                       + mainWindow.comboTextSlack
                                                model: []
                                                // Layout.preferredWidth: 120
                                                Layout.fillWidth: true
                                                delegate: ItemDelegate {
                                                    id: tokenItem

                                                    property bool opensMenu: index < tokenComboBox.itemKinds.length && tokenComboBox.itemKinds[index] === "branch"
                                                    property bool matches: tokenComboBox.matchesFilter(modelData)
                                                    // "" means the backend claimed nothing for this token.
                                                    property string tokenColor: index < tokenComboBox.itemColors.length ? tokenComboBox.itemColors[index] : ""

                                                    width: ListView.view ? ListView.view.width : implicitWidth
                                                    visible: matches
                                                    // Collapse rather than just hide, or the popup keeps the
                                                    // full-length gap where filtered-out rows used to be.
                                                    height: matches ? implicitHeight : 0
                                                    enabled: matches

                                                    contentItem: Row {
                                                        spacing: 8

                                                        Text {
                                                            width: parent.width - (tokenItem.opensMenu ? 18 : 0)
                                                            text: modelData
                                                            color: tokenItem.tokenColor !== "" ? tokenItem.tokenColor
                                                                 : mainWindow.defaultTokenColor
                                                            font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                                            elide: Text.ElideRight
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        // Marks an entry that leads to another menu
                                                        // rather than being the parameter itself.
                                                        Text {
                                                            visible: tokenItem.opensMenu
                                                            text: "\u203a"
                                                            color: "#6b7787"
                                                            font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                    }
                                                }
                                                popup: Popup {
                                                    y: tokenComboBox.height
                                                    width: Math.max(tokenComboBox.width, 240)
                                                    padding: 1

                                                    // Reset on every open: a filter left over from last time
                                                    // would silently hide most of a fresh level.
                                                    onOpened: {
                                                        filterField.text = "";
                                                        filterField.forceActiveFocus();
                                                    }
                                                    onClosed: tokenComboBox.filterText = ""

                                                    contentItem: ColumnLayout {
                                                        spacing: 0

                                                        TextField {
                                                            id: filterField

                                                            Layout.fillWidth: true
                                                            placeholderText: "Type to filter\u2026"
                                                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                            selectByMouse: true
                                                            onTextChanged: tokenComboBox.filterText = text
                                                            // Enter picks the only remaining match, so a
                                                            // narrowing search needs no mouse.
                                                            Keys.onReturnPressed: {
                                                                if (tokenComboBox.visibleCount() !== 1)
                                                                    return ;

                                                                for (let i = 0; i < tokenComboBox.model.length; ++i) {
                                                                    if (tokenComboBox.matchesFilter(tokenComboBox.model[i])) {
                                                                        tokenComboBox.currentIndex = i;
                                                                        tokenComboBox.popup.close();
                                                                        break;
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            Layout.margins: 6
                                                            visible: tokenComboBox.visibleCount() === 0
                                                            text: "No match"
                                                            color: mainWindow.unusedTextColor
                                                            font.pixelSize: mainWindow.fontSizeOfLevel[4]
                                                            font.italic: true
                                                        }

                                                        ListView {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: Math.min(contentHeight, 320)
                                                            clip: true
                                                            model: tokenComboBox.delegateModel
                                                            currentIndex: tokenComboBox.highlightedIndex

                                                            ScrollIndicator.vertical: ScrollIndicator {
                                                            }
                                                        }
                                                    }
                                                }
                                                onModelChanged: {
                                                    filterText = "";
                                                    if (model === undefined || model.length === 0) {
                                                        longestTextWidth = 0;
                                                        itemKinds = [];
                                                        itemColors = [];
                                                        return ;
                                                    }
                                                    updateLongestTextWidth();
                                                    refreshMeta();
                                                    updateNextComboBox();
                                                }
                                                onCurrentTextChanged: {
                                                    if (model === undefined || model.length === 0)
                                                        return ;

                                                    updateNextComboBox();
                                                }
                                                visible: model ? model.length > 0 : false // Enable only if there are tokens available

                                                Text {
                                                    id: dummyTextItem

                                                    visible: false
                                                    font: tokenComboBox.font
                                                }
                                                // Enable only if there are tokens available

                                            }

                                        }

                                    }

                                    ScrollBar.horizontal: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                }

                            }

                            Text {
                                text: "Current target"
                                color: syscolors.text
                                font.pixelSize: mainWindow.fontSizeOfLevel[1]
                                font.bold: true
                                Layout.alignment: Qt.AlignLeft
                            }

                            // Display current variation target
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: currentVariationTargetText.implicitHeight + 24
                                color: "#ffffff"
                                border.color: "#dddddd"
                                border.width: 1
                                radius: 4
                                anchors.margins: 5

                                Flickable {
                                    id: flickable

                                    anchors.fill: parent
                                    contentWidth: currentVariationTargetText.paintedWidth + 20
                                    contentHeight: parent.height
                                    clip: true
                                    interactive: currentVariationTargetText.paintedWidth > width
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.HorizontalFlick

                                    Text {
                                        id: currentVariationTargetText

                                        property bool allowUpdates: false // Flag to control updates

                                        function updateVariationTarget() {
                                            if (!currentVariationTargetText.allowUpdates)
                                                return ;

                                            // Skip updates if flag is false
                                            var tokens = [variedLocationComboBox.currentText];
                                            for (let i = 0; i < tokenComboBoxRepeater.count; ++i) {
                                                let text = tokenComboBoxRepeater.itemAt(i).currentText;
                                                if (text === "")
                                                    break;

                                                tokens.push(text);
                                            }
                                            currentVariationTargetText.text = Julia.get_target_path.apply(Julia, tokens);
                                            allowUpdates = false;
                                        }

                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        text: ""
                                        color: "#888888"
                                        font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                        width: implicitWidth
                                        onTextChanged: {
                                            createVariationButton.refreshLabel();
                                            variationValuesInput.refreshBlocker();
                                        }
                                    }

                                    ScrollBar.horizontal: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                }

                            }

                        }

                    }

                    // Variation values and create variation row
                    RowLayout {
                        // Variation values header
                        Text {
                            id: variationValuesHeaderText

                            text: "Variation values"
                            color: syscolors.text
                            font.bold: true
                            font.pixelSize: mainWindow.fontSizeOfLevel[1]
                            Layout.alignment: Qt.AlignLeft
                            Layout.leftMargin: 0
                        }

                        // Variation values input box
                        Rectangle {
                            id: variationValuesRectangle

                            Layout.fillWidth: true
                            Layout.preferredHeight: variationValuesInput.implicitHeight + 24
                            Layout.topMargin: 0
                            color: "#ffffff"
                            border.color: "#dddddd"
                            border.width: 1
                            radius: 4

                            ScrollView {
                                anchors.fill: parent
                                contentWidth: variationValuesInput.width + 20
                                ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                                ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                                Item {
                                    anchors.fill: parent

                                    TextInput {
                                        id: variationValuesInput

                                        // Why the variation cannot be created right now; "" when it can,
                                        // so the Create button's disabled state always has a stated reason.
                                        // A binding, so it holds from component creation and tracks the
                                        // target as well as the text.
                                        property string blocker: Julia.variation_blocker(currentVariationTargetText.text, text)

                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                        text: ""
                                        wrapMode: TextInput.NoWrap
                                        color: "black"
                                        clip: true // ensures text doesn't spill over bounds
                                        selectByMouse: true
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        // anchors.fill: parent
                                        anchors.leftMargin: 10
                                        text: "e.g. 0.1:0.2:0.5, [1.0, 1.2, 1.5], Normal(1.0, 0.2)"
                                        color: "#888888"
                                        font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                        verticalAlignment: Text.AlignVCenter
                                        visible: variationValuesInput.text === "" // Show hint text when input is empty
                                    }

                                }

                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: variationValuesInput.forceActiveFocus()
                                onDoubleClicked: variationValuesInput.selectAll()
                                // Set to false so it doesn't block text input
                                // (only used to grab focus when clicking the background)
                                hoverEnabled: true
                                preventStealing: true
                                propagateComposedEvents: true
                            }

                        }

                        // Create variation button
                        ActionButton {
                            id: createVariationButton

                            // Whether this target already has a variation decides the label.
                            // Removing one has to re-ask, or the button keeps saying "Edit"
                            // for a variation that no longer exists.
                            function refreshLabel() {
                                text = Julia.variation_exists(currentVariationTargetText.text) ? "Edit Variation" : "Create Variation";
                            }

                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 40
                            text: "Create Variation"
                            font.pixelSize: mainWindow.fontSizeOfLevel[2]
                            // Gated on the SAME predicate the Julia side uses, so the button
                            // cannot be enabled for something create_variation will refuse.
                            enabled: variationValuesInput.blocker === ""
                            // The reason, on hover, for anyone wondering why it is greyed out.
                            ToolTip.visible: hovered && !enabled && variationValuesInput.blocker !== ""
                            ToolTip.text: variationValuesInput.blocker
                            onClicked: {
                                var tokens = [currentVariationTargetText.text, variationValuesInput.text];
                                for (let i = 0; i < tokenComboBoxRepeater.count; ++i) {
                                    let text = tokenComboBoxRepeater.itemAt(i).currentText;
                                    if (text === "")
                                        break;

                                    tokens.push(text);
                                }
                                // "" means it worked. Anything else is a failure the live check
                                // could not catch, and must be shown rather than sent to stderr.
                                var err = Julia.create_variation.apply(Julia, tokens);
                                if (err !== "" && err !== undefined) {
                                    variationErrorDialog.message = err;
                                    variationErrorDialog.open();
                                    return;
                                }
                                currentVariationsFlickable.currentVariations = Julia.get_current_variations();
                                text = "Edit Variation"; // Change button text to indicate edit mode
                            }
                        }

                    }

                    // Why the variation cannot be created, stated inline rather than left to
                    // stderr. This is the GUI's first error surface; without it a click on a
                    // disabled-but-not-obviously-disabled button looked like nothing happening.
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: variationValuesInput.blocker
                        visible: text !== "" && variationValuesInput.text !== ""
                        color: "#a32a26"
                        font.pixelSize: mainWindow.fontSizeOfLevel[4]
                        wrapMode: Text.Wrap
                    }

                    // Display current variations
                    ColumnLayout {
                        id: currentVariationsColumn

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Current variations"
                                color: syscolors.text
                                font.bold: true
                                font.pixelSize: mainWindow.fontSizeOfLevel[1]
                                Layout.alignment: Qt.AlignLeft
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            ActionButton {
                                text: "Clear all"
                                font.pixelSize: mainWindow.fontSizeOfLevel[4]
                                enabled: currentVariationsFlickable.currentVariations.length > 0
                                onClicked: {
                                    Julia.clear_variations();
                                    currentVariationsFlickable.currentVariations = Julia.get_current_variations();
                                    createVariationButton.refreshLabel();
                                }
                            }
                        }

                        // Current variations rectangle
                        Flickable {
                            id: currentVariationsFlickable

                            property var currentVariations: Julia.get_current_variations()

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.fill: parent
                                color: "#fafafa"
                                radius: 6
                                border.color: "#a0a0a0"
                                border.width: 2

                                ColumnLayout {
                                    id: currentVariationPairsColumn

                                    property int maxLHSWidth: 0 // <- tracks the widest LHS

                                    anchors.fill: parent
                                    spacing: 16

                                    // Display each variation
                                    Repeater {
                                        model: currentVariationsFlickable.currentVariations

                                        Item {
                                            Layout.fillWidth: true

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 5
                                                anchors.leftMargin: 10

                                                Text {
                                                    id: lhsText

                                                    Layout.alignment: Qt.AlignRight
                                                    horizontalAlignment: Text.AlignRight
                                                    text: modelData[0].toString() + " ⇒ "
                                                    font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                    // This updates the maxLHSWidth dynamically
                                                    Component.onCompleted: {
                                                        if (lhsText.implicitWidth > currentVariationPairsColumn.maxLHSWidth)
                                                            currentVariationPairsColumn.maxLHSWidth = lhsText.implicitWidth;

                                                    }
                                                    Layout.preferredWidth: currentVariationPairsColumn.maxLHSWidth
                                                }

                                                Text {
                                                    text: modelData[1].toString()
                                                    font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.Wrap
                                                }

                                                // Until this existed the pending design could only
                                                // grow: a mistaken variation meant restarting the app.
                                                // Julia indices are 1-based; QML's `index` is 0-based.
                                                ActionButton {
                                                    text: "\u2715"
                                                    font.pixelSize: mainWindow.fontSizeOfLevel[4]
                                                    implicitWidth: 28
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Accessible.name: "Remove variation " + modelData[0].toString()
                                                    onClicked: {
                                                        Julia.delete_variation(index + 1);
                                                        currentVariationsFlickable.currentVariations = Julia.get_current_variations();
                                                        createVariationButton.refreshLabel();
                                                    }
                                                }

                                            }

                                        }

                                    }

                                    Item {
                                        Layout.fillHeight: true
                                        Layout.fillWidth: true
                                    }

                                }

                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            ScrollBar.horizontal: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                        }

                    }

                }

            }

        }

        // Bottom bar with Run Simulation button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: guiproperties.color_bottom

            // Run Simulation
            ActionButton {
                id: runSimulationButton

                property string disabledText: "Create inputs first..."

                anchors.centerIn: parent
                implicitHeight: 45
                implicitWidth: 200
                text: enabled ? "Run Simulation" : disabledText
                font.pixelSize: mainWindow.fontSizeOfLevel[1]
                font.bold: true
                enabled: false
                onClicked: {
                    // Call Julia function to run the simulation
                    // Disable button to prevent multiple clicks
                    enabled = false;
                    start_run_timer.start();
                }
            }

            Timer {
                id: start_run_timer

                running: false
                interval: 10 // 10 millisecond delay before running the simulation
                repeat: false
                onTriggered: Julia.run_simulation()
            }

        }

    }

    Dialog {
        id: variationErrorDialog

        property string message: ""

        anchors.centerIn: parent
        modal: true
        title: "Could not create the variation"
        standardButtons: Dialog.Ok
        width: Math.min(520, mainWindow.width - 80)

        Text {
            width: parent ? parent.width : 400
            text: variationErrorDialog.message
            wrapMode: Text.Wrap
            font.pixelSize: mainWindow.fontSizeOfLevel[3]
        }
    }

    JuliaSignals {
        signal simulationFinished()

        onSimulationFinished: runSimulationButton.enabled = true
    }

    Timer {
        id: testingTimer

        running: testing.testing
        onTriggered: Qt.exit(0)
    }

}
