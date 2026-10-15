pragma Singleton
import QtQuick
import Quickshell

// Shared sizes and fonts for every popup menu. Colors always come from Config.colors.
Singleton {
    id: root

    // Fonts (loaded here so menus don't depend on ids declared in shell.qml)
    readonly property string bodyFont: monaco.name
    readonly property string titleFont: charcoal.name
    readonly property string iconFont: icons.name
    readonly property int fontSize: 12
    readonly property int iconSize: 16

    // The three menu widths
    readonly property int widthSmall: 240
    readonly property int widthMedium: 320
    readonly property int widthLarge: 480

    // Spacing scale (even numbers, not a strict grid): pad 6, gap 4, rows 22, title bar 20
    readonly property int pad: 6
    readonly property int gap: 4
    readonly property int rowHeight: 22
    readonly property int titleHeight: 20

    readonly property int barHeight: 32
    readonly property int barButtonHeight: 22
    readonly property int barLabelButtonWidth: 56
    // Etched divider (menus and bar sections) and the bar-section gripper
    readonly property int separatorThickness: 6
    readonly property int gripperWidth: 4
    // Slider knob (raised bevel block, track height)
    readonly property int sliderKnobWidth: 10
    // Fits "CPU 100% 100°C RAM 100%" in Monaco (measured: 165px text + 12 padding), so the
    // sysmon button doesn't change width as numbers tick
    readonly property int barSysMonWidth: 178
    readonly property int barStatusIconSize: 12
    readonly property int barStatusFontSize: 11
    // Lyrics / now-playing line in the bar centre: Liberation Sans (Arial metrics, the Win95/98
    // UI look), bundled in fonts/ with its OFL licence. Monaco looked wavy at these sizes and
    // Charcoal too heavy.
    readonly property string barStrongFont: liberationSans.name
    readonly property int barStrongFontSize: 14

    // Component sizes
    // Launcher window: one size for every tab (Apps, Games, Clipboard) and the standalone Games menu
    readonly property int launcherWidth: 760
    readonly property int launcherHeight: 560
    // Clipboard picker: share of the width taken by the preview pane (left of the list)
    readonly property real clipPreviewFraction: 0.45
    // Screenshots: history label column, grid columns and thumbnail decode width, the pause
    // between hiding the overlay chrome and taking the shot (ms), the overlay dim, and the
    // smallest drag that counts as a region (smaller = click, ignored)
    readonly property int shotGridColumns: 4
    readonly property int shotThumbWidth: 320
    // History panel size as a fraction of the screen
    readonly property real shotHistoryWidthFraction: 0.6
    readonly property real shotHistoryHeightFraction: 0.7
    // History quick filter buttons (Today / Week / All)
    readonly property int shotFilterButtonWidth: 56
    // Games grid: columns, title strip under each cover, cover decode width, and the label
    // column of the Add game form
    readonly property int gamesGridColumns: 7
    readonly property int gamesTitleHeight: 32
    readonly property int gamesCoverDecodeWidth: 200
    readonly property int gamesLabelWidth: 72
    // Games filter chips: width, and how many days count as "Recent"
    readonly property int gamesChipWidth: 64
    readonly property int gamesRecentDays: 30
    readonly property int shotSettle: 250
    readonly property real shotDimOpacity: 0.45
    readonly property int shotMinSize: 4
    // Screen-share picker (sharepicker.qml): backdrop dim, grid columns, label strip under each card
    readonly property real shareDimOpacity: 0.35
    readonly property int shareGridColumns: 3
    readonly property int shareLabelHeight: 36
    readonly property int shareIconSize: 32
    // Spotify panel (left edge): width, cover size, recent grid columns, player poll interval
    readonly property int spotifyWidth: 400
    readonly property int spotifyCoverSize: 96
    readonly property int spotifyGridColumns: 4
    readonly property int spotifyGridColumnsLibrary: 3   // library grid tiles per row
    readonly property int spotifyRowHeight: 34      // library / song rows (two lines of 12 px text)
    readonly property int spotifyInset: 2           // padding inside the drawer's sunken fields and tiles
    readonly property int spotifyTileIcon: 32       // placeholder icon on a cover without art
    readonly property int spotifyClickGuard: 350    // ms after opening something during which clicks are ignored
    readonly property int spotifyPollMs: 2000
    readonly property int spotifyTickMs: 1000
    readonly property int spotifyVolumeStep: 300    // ms between Spotify volume calls while dragging (another device)
    readonly property int spotifyVolumeHold: 3000   // ms the slider keeps your value before trusting the source again
    readonly property color likedColor: "#1db954"    // liked heart: Spotify green (the one colour not from the palette, on request)
    readonly property int lyricsFastTick: 100
    readonly property int lyricsFontSize: 16      // Monaco hints cleanly at 12 and 16
    readonly property real lyricsAnchor: 0.38     // where the current lyric sits (0 top, 0.5 middle)
    readonly property int cheatKeyWidth: 140     // key chip column in the cheat sheet
    readonly property int searchHeight: 32
    readonly property int searchFontSize: 14
    readonly property int avatarSize: 150
    readonly property int cardWidth: 84
    readonly property int cardHeight: 68
    readonly property int swatchWidth: 10
    readonly property int swatchHeight: 34
    readonly property int calendarCell: 28
    readonly property int notificationIconSize: 32
    readonly property int notificationMargin: 12
    readonly property int barMediaMaxWidth: 420
    // Bar centre keeps the last Spotify track this long after it goes empty (track changes)
    readonly property int barHideDelay: 2000
    // How often the lyric line follows Spotify's position
    readonly property int servicesRefreshDelay: 4000 // Services panel: refresh after a doas terminal opened
    readonly property int taskInterval: 2000        // Task Manager refresh (ms)
    readonly property int taskHistory: 60           // samples per Performance graph (2 min at 2 s)
    readonly property int taskColumnWidth: 80       // CPU / Memory / Procs columns
    readonly property int sysMonInterval: 2000      // CPU / RAM / temperature read interval
    readonly property int lyricsTick: 250
    // Animations: short, no bounce. Menus fade + slide in on open (closing is instant), hover
    // highlights fade, lists scroll smoothly. 0 turns one off.
    readonly property int animOpen: 90
    readonly property int animSlide: 4
    readonly property int animHover: 60
    readonly property int animFade: 80
    readonly property int animScroll: 200
    // Idle dim layer strength (outline colour over the screen)
    readonly property real idleDimOpacity: 0.5
    // Weather refresh (wttr.in), ms
    readonly property int weatherRefresh: 1800000
    readonly property int notificationListRows: 6
    // Bluetooth menu: rows per list before it scrolls, and how long a scan runs (ms)
    readonly property int bluetoothListRows: 5
    readonly property int bluetoothScanTime: 30000
    readonly property int notificationTimeout: 10000
    readonly property int notificationFade: 400
    readonly property int osdMargin: 90
    readonly property int notificationMaxVisible: 4
    // Right-aligned value next to a meter ("100%", "MUTE")
    readonly property int valueLabelWidth: 40
    // Title bar: gap around the title, gap between title icon and text
    readonly property int titleSpacing: 8
    readonly property int titleIconGap: 6
    readonly property int traySpacing: 8
    // Unread marker on the bell: size and offset from the button's top-left
    readonly property int unreadDotSize: 6
    readonly property int unreadDotX: 4
    readonly property int unreadDotY: 3

    // Stronger bevel tones, derived from the active theme so every theme keeps working.
    // Cherry's own highlight/shadow are too close to its base (1.07:1 / 1.5:1) to read as an edge.
    readonly property color bevelLight: Qt.tint(Config.colors.base, "#b3ffffff")
    readonly property color bevelDark: Qt.darker(Config.colors.shadow, 1.7)
    // Hover / selected bar: a hard dark accent, with base-coloured text on top
    // Selection / hover bar, title bars and meter fills. Use the theme's own accent (cherry:
    // the original linux-retroism #c950bb) with whichever palette text colour (base, text or
    // outline) reads best on it. Only if none reaches 4.5:1 is the accent darkened until base
    // text does. selectText is the matching text colour.
    readonly property var selectPair: {
        const acc = Config.colors.accent;
        let best = null, bestC = 0;
        for (const c of [Config.colors.base, Config.colors.text, Config.colors.outline]) {
            const k = root.contrast(c, acc);
            if (k > bestC) { bestC = k; best = c; }
        }
        if (bestC >= 4.5)
            return { bar: acc, text: best };
        let f = 1.0;
        while (f < 2.0 && root.contrast(Config.colors.base, Qt.darker(acc, f)) < 4.5)
            f += 0.05;
        return { bar: Qt.darker(acc, f), text: Config.colors.base };
    }
    readonly property color selectBar: selectPair.bar
    readonly property color selectText: selectPair.text
    function luminance(c) {
        // Config.colors holds strings ("#e3b9d6"); Qt.darker(x, 1) turns either form into a color
        const col = Qt.darker(c, 1.0);
        const ch = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * ch(col.r) + 0.7152 * ch(col.g) + 0.0722 * ch(col.b);
    }
    function contrast(a, b) {
        const la = luminance(a), lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    // Frame geometry: 1px outline + 2px bevel + 1px gap, then the title bar, then a 1px outlined
    // content box (the double frame), then padding inside that box.
    readonly property int frameInset: 4
    readonly property int boxGap: 2
    readonly property int boxPadH: 5
    readonly property int boxPadV: 4
    readonly property int chromeTop: frameInset + titleHeight + boxGap + 1 + boxPadV
    readonly property int chromeBottom: frameInset + 1 + boxPadV
    readonly property int chromeHeight: chromeTop + chromeBottom

    FontLoader {
        id: monaco
        source: Qt.resolvedUrl("fonts/Monaco.ttf")
    }
    FontLoader {
        id: charcoal
        source: Qt.resolvedUrl("fonts/Charcoal.ttf")
    }
    FontLoader {
        id: liberationSans
        source: Qt.resolvedUrl("fonts/LiberationSans-Regular.ttf")
    }
    FontLoader {
        id: icons
        source: Qt.resolvedUrl("fonts/MaterialSymbolsSharp_Filled_20pt-Bold.ttf")
    }
}
