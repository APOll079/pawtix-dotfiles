pragma Singleton
import Quickshell

Singleton {

    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values).sort((a, b) => a.name.localeCompare(b.name))

    readonly property var preppedNames: list.map(a => ({
                name: Fuzzy.prepare(`${a.name} `),
                entry: a
            }))

    // Fuzzy search that keeps fuzzysort's score (0..1) so callers can blend in usage
    function scoredQuery(search: string): var {
        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => ({ entry: r.obj.entry, score: r.score }));
    }

    function getIcon(iconName) {
        if (!iconName || iconName.length == 0)
            return "";
        return Quickshell.iconPath(iconName, true);
    }
}
