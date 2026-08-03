// Everything the weather card decides, on the QtQuick-only side of the line
// (#50).
//
// The service next door is three network calls and a cache write; this is what
// those calls *say* — the URLs they are made against, the shape of the answers,
// the words and glyphs a WMO code turns into, and when a cached forecast has
// gone stale. All of it is text in and values out, so `tests/` reaches it under
// qmltestrunner (CLAUDE.md, seam 1) and the untestable half stays as small as a
// `Process` and a timer.
//
// ## Open-Meteo, and why there is no key here
//
// #9 picked Open-Meteo for the dashboard card, and the reason it survived the
// pass is that it is keyless: a weather card that needed an API key would be a
// card that is blank on a fresh install until the user goes and registers for
// something. Two endpoints are used and they are separate services on separate
// hosts — geocoding turns "Boston" into a latitude, forecast turns a latitude
// into a temperature — which is why `geocodeUrl` and `forecastUrl` do not share
// a base.
//
// The third endpoint is the optional auto mode: asked for by writing `auto` as
// the place, it asks a geolocation service what this IP looks like. That is the
// one call this shell makes that says something about the user *to* a third
// party rather than only asking it something, so it is opt-in by a word rather
// than by a blank field — `mode` below is where that is decided.
//
// ## Codes, not conditions
//
// Open-Meteo answers a WMO 4677 weather code and nothing else — no icon name,
// no phrase. Both tables below are therefore ours, and they are here rather
// than in the card for the usual reason: "code 45 is fog" is a decision with a
// right answer, and a decision with a right answer belongs where a test can ask
// it.
import QtQuick

QtObject {
    id: root

    // --- the endpoints --------------------------------------------------------

    readonly property string geocodeBase: "https://geocoding-api.open-meteo.com/v1/search"
    readonly property string forecastBase: "https://api.open-meteo.com/v1/forecast"

    /// The auto-location service. Keyless, HTTPS, and asked at most once a
    /// session — see the header on what it costs.
    ///
    /// `ipwho.is` and not `ipapi.co`, which was here first and was measured
    /// answering `{"error": true, "reason": "RateLimited"}` with a 200 from an
    /// ordinary home address — a free tier shared across everyone behind one
    /// IP. A rate-limited answer is indistinguishable from a working one at the
    /// HTTP layer, which is why `parseIp` below reads the body's own success
    /// flag rather than trusting the status code.
    readonly property string ipBase: "https://ipwho.is/"

    /// The two unit systems, as the config spells them
    /// (`weatherTime.weather.units`).
    readonly property var unitSystems: ["metric", "imperial"]

    function metric(units: string): bool {
        return units !== "imperial";
    }

    /// What the configured place asks the shell to do: `unset`, `auto` — #9's
    /// IP-based mode — or `place`, a name to geocode.
    ///
    /// Three answers and not two, which is the whole of the auto mode's
    /// opt-in: an unconfigured card makes no request at all, rather than
    /// treating "the user has not said" as permission to ask a geolocation
    /// service about this address. Core/SettingsSchema.qml says the same thing
    /// at the key.
    ///
    /// Untyped, unlike its neighbours: a declared `string` parameter turns a
    /// JavaScript `null` into the four characters "null", and this is the one
    /// function here that is asked about a key that may be absent.
    function mode(place): string {
        const name = String(place ?? "").trim();
        if (name === "")
            return "unset";
        return name.toLowerCase() === "auto" ? "auto" : "place";
    }

    /// A place name to one candidate. `count=1` because the card shows one
    /// place: offering a disambiguation list would be a settings control (#55)
    /// and not a card.
    function geocodeUrl(place: string): string {
        return root.geocodeBase + "?name=" + encodeURIComponent(String(place ?? "").trim())
             + "&count=1&language=en&format=json";
    }

    /// Current conditions plus the daily rows the card draws under them.
    ///
    /// `timezone=auto` is what makes a day boundary mean the *forecast's* day
    /// rather than UTC's — without it a card configured for Tokyo shows
    /// yesterday's high all morning. The unit parameters are passed rather than
    /// converted here for the same reason: the API rounds in the unit it
    /// reports, so converting a Celsius answer would show a temperature nobody
    /// else's forecast agrees with.
    function forecastUrl(latitude: real, longitude: real, units: string, days: int): string {
        const span = Math.max(1, Math.min(7, Math.round(days || 1)));
        return root.forecastBase
             + "?latitude=" + Number(latitude).toFixed(4)
             + "&longitude=" + Number(longitude).toFixed(4)
             + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
             + "wind_speed_10m,weather_code,is_day"
             + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             + "&timezone=auto&forecast_days=" + span
             + "&temperature_unit=" + (root.metric(units) ? "celsius" : "fahrenheit")
             + "&wind_speed_unit=" + (root.metric(units) ? "kmh" : "mph");
    }

    // --- reading the answers --------------------------------------------------
    //
    // Every parser takes the response body as text and answers `null` for
    // anything it cannot use. `null` and not a partly-filled object: a card
    // drawn from half a forecast is a card showing a temperature with no
    // condition under it, which reads as a bug in the shell rather than as a
    // request that failed.

    function json(text: string): var {
        try {
            const value = JSON.parse(String(text ?? ""));
            return (value !== null && typeof value === "object") ? value : null;
        } catch (error) {
            return null;
        }
    }

    function number(value): real {
        const parsed = Number(value);
        return (value === null || value === undefined || value === "" || isNaN(parsed))
               ? NaN : parsed;
    }

    /// `{ label, latitude, longitude }` for the first candidate, or null.
    ///
    /// The label is the place plus its region, because a bare "Springfield" on
    /// a card is a claim the user cannot check. The region is dropped when the
    /// service does not supply one rather than left as an empty comma.
    function parseGeocode(text: string): var {
        const body = root.json(text);
        const results = body && Array.isArray(body.results) ? body.results : [];
        if (results.length === 0)
            return null;

        const hit = results[0];
        const latitude = root.number(hit.latitude);
        const longitude = root.number(hit.longitude);
        if (isNaN(latitude) || isNaN(longitude))
            return null;

        const parts = [hit.name, hit.admin1, hit.country_code].filter(
            part => part !== undefined && part !== null && String(part) !== "");
        return {
            label: parts.join(", "),
            latitude: latitude,
            longitude: longitude
        };
    }

    /// The same shape, from the IP service. A city and a region is all this
    /// card ever shows of it.
    function parseIp(text: string): var {
        const body = root.json(text);
        if (body === null)
            return null;
        // A refusal, answered with a 200. See the note on `ipBase`.
        if (body.success === false || body.error === true)
            return null;

        const latitude = root.number(body.latitude);
        const longitude = root.number(body.longitude);
        if (isNaN(latitude) || isNaN(longitude))
            return null;

        const parts = [body.city, body.region_code || body.region, body.country_code].filter(
            part => part !== undefined && part !== null && String(part) !== "");
        return {
            label: parts.length > 0 ? parts.join(", ") : "Here",
            latitude: latitude,
            longitude: longitude
        };
    }

    /// `{ current: { temperature, feelsLike, humidity, wind, code, day },
    ///    days: [{ date, code, high, low }] }`, or null.
    ///
    /// The daily rows are optional and the current block is not: a forecast
    /// with no rows is a shorter card, and one with no temperature is not a
    /// weather card at all.
    function parseForecast(text: string): var {
        const body = root.json(text);
        const current = body && body.current !== undefined ? body.current : null;
        if (current === null || typeof current !== "object")
            return null;

        const temperature = root.number(current.temperature_2m);
        if (isNaN(temperature))
            return null;

        return {
            current: {
                temperature: temperature,
                feelsLike: root.number(current.apparent_temperature),
                humidity: root.number(current.relative_humidity_2m),
                wind: root.number(current.wind_speed_10m),
                code: root.number(current.weather_code),
                // Absent `is_day` reads as day: a sun on a clear night is a
                // wrong glyph, and a moon at noon is a broken one.
                day: current.is_day === undefined ? true : Number(current.is_day) !== 0
            },
            days: root.parseDays(body.daily)
        };
    }

    function parseDays(daily: var): var {
        if (daily === null || daily === undefined || !Array.isArray(daily.time))
            return [];

        const codes = Array.isArray(daily.weather_code) ? daily.weather_code : [];
        const highs = Array.isArray(daily.temperature_2m_max) ? daily.temperature_2m_max : [];
        const lows = Array.isArray(daily.temperature_2m_min) ? daily.temperature_2m_min : [];

        const out = [];
        for (let i = 0; i < daily.time.length; i++) {
            const high = root.number(highs[i]);
            const low = root.number(lows[i]);
            // A row the API left a hole in is dropped rather than drawn as a
            // dash: the row's whole content is two numbers.
            if (isNaN(high) || isNaN(low))
                continue;
            out.push({
                date: String(daily.time[i]),
                code: root.number(codes[i]),
                high: high,
                low: low
            });
        }
        return out;
    }

    // --- what a code means ----------------------------------------------------

    /// WMO 4677, grouped the way a person reads a sky rather than the way the
    /// table is numbered: the difference between 61 and 63 is "rain" either
    /// way, and a card that said "slight rain" against "moderate rain" would be
    /// making a distinction nobody acts on. Intensity survives only where it
    /// changes what you would do — freezing and thunder.
    ///
    /// One table and not two, which it was first: a word and a glyph read off
    /// separate `switch`es is one code added in two places, and the day the two
    /// disagree the card says "Snow" over a raincloud.
    ///
    /// `night` is given only for the two codes where the sky itself is the
    /// picture — clear and mainly clear. A moon behind rain is a detail nobody
    /// looks for and four more glyph names to keep vendored.
    readonly property var conditions: ({
        0: { label: "Clear", icon: "sun", night: "moon" },
        1: { label: "Mainly clear", icon: "cloud-sun", night: "cloud-moon" },
        2: { label: "Partly cloudy", icon: "cloud-sun" },
        3: { label: "Overcast", icon: "cloudy" },
        45: { label: "Fog", icon: "cloud-fog" },
        48: { label: "Fog", icon: "cloud-fog" },
        51: { label: "Drizzle", icon: "cloud-drizzle" },
        53: { label: "Drizzle", icon: "cloud-drizzle" },
        55: { label: "Drizzle", icon: "cloud-drizzle" },
        56: { label: "Freezing drizzle", icon: "cloud-drizzle" },
        57: { label: "Freezing drizzle", icon: "cloud-drizzle" },
        61: { label: "Rain", icon: "cloud-rain" },
        63: { label: "Rain", icon: "cloud-rain" },
        65: { label: "Rain", icon: "cloud-rain" },
        66: { label: "Freezing rain", icon: "cloud-hail" },
        67: { label: "Freezing rain", icon: "cloud-hail" },
        71: { label: "Snow", icon: "cloud-snow" },
        73: { label: "Snow", icon: "cloud-snow" },
        75: { label: "Snow", icon: "cloud-snow" },
        77: { label: "Snow", icon: "cloud-snow" },
        80: { label: "Rain showers", icon: "cloud-rain-wind" },
        81: { label: "Rain showers", icon: "cloud-rain-wind" },
        82: { label: "Rain showers", icon: "cloud-rain-wind" },
        85: { label: "Snow showers", icon: "cloud-snow" },
        86: { label: "Snow showers", icon: "cloud-snow" },
        95: { label: "Thunderstorm", icon: "cloud-lightning" },
        96: { label: "Thunderstorm with hail", icon: "cloud-lightning" },
        99: { label: "Thunderstorm with hail", icon: "cloud-lightning" }
    })

    /// The row for a code, or null for one this table has never heard of — a
    /// forecast from a newer WMO revision, or a service having a bad day.
    function condition(code: var): var {
        const value = root.number(code);
        if (isNaN(value))
            return null;
        const row = root.conditions[Math.round(value)];
        return row === undefined ? null : row;
    }

    function conditionLabel(code: var): string {
        const row = root.condition(code);
        return row === null ? "Unknown" : row.label;
    }

    function conditionIcon(code: var, day: bool): string {
        const row = root.condition(code);
        if (row === null)
            return "cloud-off";
        return (day === false && row.night !== undefined) ? row.night : row.icon;
    }

    // --- words ----------------------------------------------------------------

    /// A temperature, rounded and degree-signed. No unit letter: the card shows
    /// one place in one system, and a `°C` on every one of six numbers is five
    /// repetitions of a thing the user configured themselves.
    function temperature(value: var): string {
        const parsed = root.number(value);
        return isNaN(parsed) ? "—" : Math.round(parsed) + "°";
    }

    function windLabel(value: var, units: string): string {
        const parsed = root.number(value);
        return isNaN(parsed) ? "" : Math.round(parsed) + (root.metric(units) ? " km/h" : " mph");
    }

    function humidityLabel(value: var): string {
        const parsed = root.number(value);
        return isNaN(parsed) ? "" : Math.round(parsed) + "%";
    }

    /// The small print under the reading: what it feels like, how humid, how
    /// windy — and only the parts the service actually answered. A middle dot
    /// with nothing on one side of it is worse than a shorter line.
    ///
    /// Here rather than in the card because it is a decision with a right
    /// answer, which is the rule the seams are drawn on (CLAUDE.md): the card
    /// draws a string, and what is in the string is checked at seam 1.
    function detailLine(current: var, units: string): string {
        if (current === null || current === undefined)
            return "";

        const parts = [];
        if (!isNaN(root.number(current.feelsLike)))
            parts.push("feels " + root.temperature(current.feelsLike));
        const humidity = root.humidityLabel(current.humidity);
        if (humidity !== "")
            parts.push(humidity + " humidity");
        const wind = root.windLabel(current.wind, units);
        if (wind !== "")
            parts.push(wind);
        return parts.join(" · ");
    }

    /// What the card says when it has no reading: nowhere configured, a lookup
    /// that failed, or a request still in flight.
    ///
    /// Three sentences and not a blank card, which is #81's rule inside a
    /// surface — and the unconfigured one is both the common case on a fresh
    /// install and the only one the reader can act on, so it names the key.
    function emptyMessage(status: string, why: string): string {
        switch (status) {
        case "unset":
            return "Set weatherTime.weather.place to a town, or to “auto”.";
        case "failed":
            return String(why ?? "") !== "" ? why : "The forecast could not be read.";
        }
        return "Checking the weather…";
    }

    /// The glyph beside that sentence. A pin for "tell me where you are", a
    /// struck-through cloud for a service that would not answer.
    function emptyIcon(status: string): string {
        return status === "failed" ? "cloud-off" : "map-pin";
    }

    /// The row heading in the forecast strip: `Today`, then three letters of
    /// the weekday.
    ///
    /// Built from the ISO date rather than from a `Date`, for the reason
    /// Surfaces/Drawers/CalendarPolicy.qml gives at length — a `Date` parsed
    /// from `2026-08-03` is a UTC instant, and rendering it in a timezone west
    /// of Greenwich moves it to the day before.
    function dayLabel(iso: string, todayIso: string): string {
        const text = String(iso ?? "");
        const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(text);
        if (!match)
            return "";
        if (text.slice(0, 10) === String(todayIso ?? "").slice(0, 10))
            return "Today";
        const weekday = new Date(parseInt(match[1], 10),
                                 parseInt(match[2], 10) - 1,
                                 parseInt(match[3], 10)).getDay();
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday];
    }

    /// Today, as the API spells it, from a local `Date` — the other half of
    /// `dayLabel`'s argument, and here so that the one place that knows this
    /// format is this file.
    function isoDate(when: var): string {
        const date = (when instanceof Date) ? when : new Date();
        const month = date.getMonth() + 1;
        const day = date.getDate();
        return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month
             + "-" + (day < 10 ? "0" : "") + day;
    }

    // --- the cache ------------------------------------------------------------
    //
    // What is cached is the *answer*, in `state.json` (Core/StateSchema.qml,
    // `weather.cache`), and what it buys is a card that draws immediately on
    // the next shell start instead of after two round trips. A forecast is not
    // setup and never travels between machines, which is why it is state and
    // not config (#21).

    /// The whole cache entry. `place` and `units` are stored beside the reading
    /// because both invalidate it: a card configured for Lisbon must not draw
    /// Boston's temperature for one frame, and 24 is a mild day in one system
    /// and a cold one in the other.
    function cacheEntry(place: string, units: string, location: var, forecast: var,
                        nowMs: real): var {
        return {
            place: String(place ?? ""),
            units: String(units ?? ""),
            label: location ? location.label : "",
            latitude: location ? location.latitude : NaN,
            longitude: location ? location.longitude : NaN,
            fetchedAt: Math.round(nowMs),
            current: forecast ? forecast.current : null,
            days: forecast ? forecast.days : []
        };
    }

    /// Whether a cache entry may be drawn at all — the same place, the same
    /// units, and a reading in it. Age is a separate question (`stale`): an old
    /// forecast is still the best answer there is while the new one is in
    /// flight, and blanking the card during a refresh would make every refresh
    /// visible.
    function usable(cache: var, place: string, units: string): bool {
        if (cache === null || cache === undefined || typeof cache !== "object")
            return false;
        if (cache.current === null || cache.current === undefined)
            return false;
        return String(cache.place ?? "") === String(place ?? "")
            && String(cache.units ?? "") === String(units ?? "");
    }

    /// Whether it is old enough to refetch. A cache from the future — a clock
    /// corrected backwards, a file copied from another machine — is stale
    /// rather than eternally fresh.
    function stale(cache: var, nowMs: real, refreshMinutes: int): bool {
        if (cache === null || cache === undefined || typeof cache !== "object")
            return true;
        const fetched = root.number(cache.fetchedAt);
        if (isNaN(fetched))
            return true;
        const age = nowMs - fetched;
        return age < 0 || age >= Math.max(1, refreshMinutes) * 60000;
    }

    /// The known location out of a cache, when the configured place has not
    /// changed — what saves the geocoding call on every start.
    function cachedLocation(cache: var, place: string): var {
        if (cache === null || cache === undefined || typeof cache !== "object")
            return null;
        if (String(cache.place ?? "") !== String(place ?? ""))
            return null;
        const latitude = root.number(cache.latitude);
        const longitude = root.number(cache.longitude);
        if (isNaN(latitude) || isNaN(longitude))
            return null;
        return { label: String(cache.label ?? ""), latitude: latitude, longitude: longitude };
    }

    // --- the log line ---------------------------------------------------------

    /// What the service says once a fetch lands, and what
    /// `tools/drawer-harness.sh` asserts on (#81: a surface gets a line per
    /// state change worth checking).
    function summary(label: string, forecast: var): string {
        if (forecast === null || forecast === undefined)
            return "no forecast for " + (label || "nowhere");
        return (label || "here") + " " + root.temperature(forecast.current.temperature)
             + " " + root.conditionLabel(forecast.current.code).toLowerCase()
             + ", " + forecast.days.length + " day(s)";
    }
}
