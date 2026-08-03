pragma Singleton

// The weather facade (#50, #12 §3).
//
//     Weather.label      // "Boston, Massachusetts, US"
//     Weather.current    // { temperature, feelsLike, humidity, wind, code, day }
//     Weather.days       // [{ date, code, high, low }] — the forecast strip
//     Weather.status     // "idle" | "locating" | "loading" | "ready" | "failed"
//     Weather.watch() / Weather.release()   // while the card is on screen
//
// Two decisions, made in Services/Weather/WeatherPolicy.qml where `tests/` can
// reach them: what the three URLs are, and what the answers mean. What is left
// here is the fetching, the cache write, and the rule about when a fetch is
// allowed to happen at all.
//
// ## Nothing at startup, and nothing while nobody is looking
//
// #50's acceptance criterion is that the shell pays no network cost at startup,
// and the idle budget (#22 §5) asks for the second half of it: this card is
// behind a drawer that is shut most of the day, and a poll running behind it
// would be a wakeup nobody is paying for. So:
//
//   - the deferred stage reads the **cache** out of `state.json` and fetches
//     nothing. A shell that has run before therefore opens its first dashboard
//     with a temperature already in it;
//   - a fetch happens when the card appears (`watch()`) and the reading is
//     stale, and when the configured place or units change under an open card;
//   - the refresh timer runs only while `watchers > 0`, which is to say only
//     while the dashboard is open with the weather card in it.
//
// The visible consequence is deliberate: leaving the dashboard open across the
// refresh interval updates the card, and a forecast that went stale overnight
// is refreshed a second after the panel opens rather than before.
//
// ## XMLHttpRequest, not curl
//
// The only HTTP this shell makes. It goes through the QML engine's own client
// rather than through a `Process`, which is the opposite of the choice
// Services/Networking/Vpn.qml and Services/Launcher/Calculator.qml make — and
// for the reason those two document in reverse: they wrap a *tool* whose
// absence is a real state the shell has to report, while `curl` here would be a
// dependency added for nothing. There is no exit status to read (#78) because
// there is no process; the HTTP status is read instead, and every failure path
// ends at the same `fail()`.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    readonly property WeatherPolicy policy: WeatherPolicy {}

    /// Where the reading is from, as the geocoder or the IP service named it.
    property string label: ""

    /// `{ temperature, feelsLike, humidity, wind, code, day }`, or null before
    /// the first answer.
    property var current: null

    /// `[{ date, code, high, low }]` — one row per day in the strip.
    property var days: []

    /// `idle` before anything has been asked, then `locating` → `loading` →
    /// `ready`, or `failed`; `unset` for a card that has not been told where it
    /// is. The card draws the difference: a shell that has never fetched, one
    /// whose fetch failed and one nobody has configured are three different
    /// things to say.
    property string status: "idle"

    /// Why the last attempt failed, for the card's one line of small print.
    property string message: ""

    readonly property bool ready: root.current !== null

    // --- what the config asked for --------------------------------------------

    readonly property var settings: Config.values.weatherTime.weather

    /// The place as configured, and what it asks for: `unset`, `auto` or
    /// `place` (Services/Weather/WeatherPolicy.qml).
    readonly property string place: root.settings.place
    readonly property string mode: root.policy.mode(root.place)
    readonly property string units: root.settings.units

    /// Where the forecast is for, once something has resolved it.
    property var location: null

    // --- who is looking -------------------------------------------------------

    /// How many surfaces have the card on screen. The weather card takes one
    /// while it exists; nothing else does.
    property int watchers: 0

    function watch(): void {
        root.watchers += 1;
        // The one place a fetch is triggered by a *surface*: opening the
        // dashboard onto a stale forecast refreshes it, and opening it onto a
        // fresh one costs nothing.
        root.refresh(false);
    }

    function release(): void {
        root.watchers = Math.max(0, root.watchers - 1);
    }

    // --- fetching -------------------------------------------------------------

    /// Bring the reading up to date. `force` skips the staleness check, which
    /// is what a changed place or a changed unit system needs — both invalidate
    /// a cache that is otherwise minutes old.
    function refresh(force: bool): void {
        if (inFlight.running)
            return;
        // Nowhere configured is not a failure and not a request: the card says
        // so, and nothing is asked of anybody. See the schema key.
        if (root.mode === "unset") {
            root.status = "unset";
            return;
        }
        if (!force && !root.policy.stale(root.cache, Date.now(),
                                         root.settings.refreshMinutes))
            return;

        if (root.location === null) {
            root.locate();
            return;
        }
        root.loadForecast();
    }

    /// Turn the configured place into coordinates — or, with no place
    /// configured, ask what this IP looks like.
    function locate(): void {
        root.status = "locating";
        if (root.mode === "auto") {
            root.get(root.policy.ipUrl(), body => {
                const found = body === null ? null : root.policy.parseIp(body);
                if (found === null) {
                    root.fail("could not work out where this machine is");
                    return;
                }
                root.located(found);
            });
            return;
        }

        root.get(root.policy.geocodeUrl(root.place), body => {
            const found = body === null ? null : root.policy.parseGeocode(body);
            if (found === null) {
                // The one failure that is the user's to fix, so it names what
                // was asked for rather than saying "lookup failed".
                root.fail("no such place: " + root.place);
                return;
            }
            root.located(found);
        });
    }

    function located(found: var): void {
        root.location = found;
        root.label = found.label;
        root.loadForecast();
    }

    function loadForecast(): void {
        root.status = "loading";
        root.get(root.policy.forecastUrl(root.location.latitude, root.location.longitude,
                                         root.units, root.settings.days),
                 body => {
            const forecast = body === null ? null : root.policy.parseForecast(body);
            if (forecast === null) {
                root.fail("the forecast could not be read");
                return;
            }
            root.publish(forecast);
        });
    }

    function publish(forecast: var): void {
        root.current = forecast.current;
        root.days = forecast.days;
        root.status = "ready";
        root.message = "";

        root.cache = root.policy.cacheEntry(root.place, root.units, root.location,
                                            forecast, Date.now());
        ShellState.set("weather.cache", root.cache);

        Logger.log("weather", root.policy.summary(root.label, forecast));
    }

    /// Every failure path ends here. The last good reading is **kept**: a card
    /// that blanked itself because one request timed out would be a worse
    /// answer than a forecast from twenty minutes ago, which is still the
    /// weather.
    function fail(why: string): void {
        root.status = root.ready ? "ready" : "failed";
        root.message = why;
        Logger.warn("weather", why);
    }

    // --- the cache ------------------------------------------------------------
    //
    // In `state.json` and not in settings, because a forecast is not setup and
    // never travels between machines (#21). Core/StateSchema.qml holds the key.

    property var cache: ({})

    function restore(): void {
        if (root.mode === "unset") {
            root.status = "unset";
            Logger.log("weather", "no place configured — the card is asking for one");
            return;
        }

        const stored = ShellState.values.weather.cache;
        if (!root.policy.usable(stored, root.place, root.units)) {
            // A cache for another place is not thrown away here — the next
            // successful fetch overwrites it — but it is not drawn either.
            Logger.log("weather", "no cached reading for " + root.place);
            return;
        }

        root.cache = stored;
        root.location = root.policy.cachedLocation(stored, root.place);
        root.label = stored.label;
        root.current = stored.current;
        root.days = Array.isArray(stored.days) ? stored.days : [];
        root.status = "ready";
        Logger.log("weather", "cached " + root.policy.summary(root.label,
                   { current: root.current, days: root.days }));
    }

    // --- the requests ---------------------------------------------------------

    /// One GET, answered with the body or with null. Everything above branches
    /// on that one distinction, so a 404, a 500, a DNS failure and a machine
    /// with no network at all arrive at the same place.
    function get(url: string, done: var): void {
        const request = new XMLHttpRequest();
        inFlight.request = request;
        inFlight.restart();

        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            inFlight.stop();
            inFlight.request = null;
            done(request.status === 200 ? request.responseText : null);
        };

        request.open("GET", url);
        request.send();
    }

    /// The deadline, because a QML `XMLHttpRequest` has no timeout of its own:
    /// a connection that opens and then stalls — a captive portal, a laptop
    /// carried out of range mid-request — would otherwise leave `inFlight.running`
    /// true forever and no later refresh could ever start.
    Timer {
        id: inFlight

        property var request: null

        interval: 15000
        onTriggered: {
            if (inFlight.request !== null) {
                inFlight.request.abort();
                inFlight.request = null;
            }
            root.fail("the weather service did not answer");
        }
    }

    /// The refresh, running only while the card is on screen — see the header.
    Timer {
        interval: Math.max(1, root.settings.refreshMinutes) * 60000
        repeat: true
        running: root.watchers > 0
        onTriggered: root.refresh(true)
    }

    // A place or a unit system changed under an open card: the reading on
    // screen is now for somewhere else, or in the other scale.
    Connections {
        target: Config

        function onKeyChanged(path, value, previous) {
            if (path !== "weatherTime.weather.place" && path !== "weatherTime.weather.units")
                return;
            if (path === "weatherTime.weather.place")
                root.location = null;
            root.current = null;
            root.days = [];
            root.status = "idle";
            if (root.watchers > 0)
                root.refresh(true);
        }
    }

    // Deferred, and a *read* rather than a fetch: the cache is a file, and the
    // first request waits for someone to open the dashboard.
    Connections {
        target: Startup
        function onDeferredStage() { root.restore(); }
    }

    Component.onCompleted: if (Startup.deferredRan) root.restore();
}
