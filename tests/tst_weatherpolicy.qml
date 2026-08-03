// The weather card's decisions (#50): what Open-Meteo is asked, what comes
// back, what a WMO code means, and when a cached forecast has stopped counting.
//
// Seam 1 (CLAUDE.md): every one of these is text in and a value out, so the
// service next door is left holding only the parts a compositor and a network
// are needed for — an XMLHttpRequest, a timer and a state write.
import QtQuick
import QtTest
import "../Services/Weather"

TestCase {
    name: "WeatherPolicy"

    WeatherPolicy { id: policy }

    // --- what the configured place asks for -----------------------------------

    function test_a_place_name_is_geocoded_and_the_word_auto_is_not() {
        compare(policy.mode("Boston"), "place");
        compare(policy.mode("auto"), "auto");
        compare(policy.mode("Auto"), "auto");
        compare(policy.mode("  auto  "), "auto");
    }

    function test_an_unconfigured_card_asks_nobody_anything() {
        // The auto mode is opt-in and not a default: "the user has not said
        // where they are" is not permission to ask a geolocation service about
        // their address (Core/SettingsSchema.qml says the same at the key).
        compare(policy.mode(""), "unset");
        compare(policy.mode("   "), "unset");
        compare(policy.mode(null), "unset");
        compare(policy.mode(undefined), "unset");
    }

    // --- the requests ---------------------------------------------------------

    function test_a_place_with_a_space_in_it_survives_the_url() {
        // The failure this prevents is not an error: an unencoded space makes a
        // URL the service answers 400 to, and a card that says "no forecast"
        // for New York is indistinguishable from one that has no network.
        const url = policy.geocodeUrl("New York");
        verify(url.indexOf("name=New%20York") > 0, url);
        verify(url.indexOf("count=1") > 0, url);
    }

    function test_a_place_is_trimmed_before_it_is_asked_for() {
        verify(policy.geocodeUrl("  Lisbon  ").indexOf("name=Lisbon&") > 0);
    }

    function test_the_forecast_asks_for_the_configured_units() {
        const metric = policy.forecastUrl(42.36, -71.06, "metric", 4);
        verify(metric.indexOf("temperature_unit=celsius") > 0, metric);
        verify(metric.indexOf("wind_speed_unit=kmh") > 0, metric);

        const imperial = policy.forecastUrl(42.36, -71.06, "imperial", 4);
        verify(imperial.indexOf("temperature_unit=fahrenheit") > 0, imperial);
        verify(imperial.indexOf("wind_speed_unit=mph") > 0, imperial);
    }

    function test_the_forecast_asks_for_local_days() {
        // Without `timezone=auto` a day boundary is UTC's, and a card
        // configured for Tokyo shows yesterday's high all morning.
        verify(policy.forecastUrl(35.68, 139.69, "metric", 4).indexOf("timezone=auto") > 0);
    }

    function test_a_hand_edited_day_count_cannot_ask_for_a_forecast_nobody_serves() {
        verify(policy.forecastUrl(0, 0, "metric", 99).indexOf("forecast_days=7") > 0);
        verify(policy.forecastUrl(0, 0, "metric", 0).indexOf("forecast_days=1") > 0);
    }

    function test_the_coordinates_are_not_rendered_in_exponent_notation() {
        // `String(1e-7)` is `1e-7`, which the API reads as a missing latitude.
        const url = policy.forecastUrl(0.00000012, -71.06, "metric", 1);
        verify(url.indexOf("e-") < 0, url);
    }

    // --- reading the answers --------------------------------------------------

    readonly property string geocodeBody: JSON.stringify({
        results: [{ name: "Boston", admin1: "Massachusetts", country_code: "US",
                    latitude: 42.35843, longitude: -71.05977 }]
    })

    function test_a_geocode_answer_becomes_a_label_and_a_pair_of_coordinates() {
        const hit = policy.parseGeocode(geocodeBody);
        compare(hit.label, "Boston, Massachusetts, US");
        compare(Math.round(hit.latitude * 100), 4236);
        compare(Math.round(hit.longitude * 100), -7106);
    }

    function test_a_place_the_service_has_never_heard_of_is_null_rather_than_empty() {
        // The caller branches on this: an empty object would be a card drawn
        // for a place with no name at 0°N 0°E, which is in the Atlantic.
        compare(policy.parseGeocode(JSON.stringify({ results: [] })), null);
        compare(policy.parseGeocode(JSON.stringify({ error: true })), null);
    }

    function test_a_truncated_response_does_not_throw() {
        // What a dropped connection actually delivers: a body that is not JSON
        // at all, or half of one.
        compare(policy.parseGeocode('{"results": [{"name": "Bos'), null);
        compare(policy.parseGeocode(""), null);
        compare(policy.parseForecast("<html>502 Bad Gateway</html>"), null);
        compare(policy.parseIp(""), null);
    }

    function test_a_candidate_with_no_coordinates_is_not_a_location() {
        compare(policy.parseGeocode(JSON.stringify({ results: [{ name: "Nowhere" }] })), null);
    }

    function test_a_place_with_no_region_is_labelled_without_a_dangling_comma() {
        const hit = policy.parseGeocode(JSON.stringify({
            results: [{ name: "Singapore", country_code: "SG",
                        latitude: 1.28, longitude: 103.85 }]
        }));
        compare(hit.label, "Singapore, SG");
    }

    function test_the_ip_service_answers_the_same_shape_as_the_geocoder() {
        // Both feed one consumer, so the two parsers agree on the shape or the
        // service has to branch on where its location came from.
        const hit = policy.parseIp(JSON.stringify({
            success: true, city: "Boston", region: "Massachusetts", region_code: "MA",
            country_code: "US", latitude: 42.35, longitude: -71.06
        }));
        compare(hit.label, "Boston, MA, US");
        compare(Math.round(hit.latitude), 42);
    }

    function test_a_rate_limited_lookup_is_a_failure_and_not_a_location() {
        // Measured against the service this used before: a free tier shared
        // across a whole address answers `{"error": true}` with a **200**, so
        // the status code is not the thing to read.
        compare(policy.parseIp(JSON.stringify({ error: true, reason: "RateLimited" })), null);
        compare(policy.parseIp(JSON.stringify({ success: false, message: "Invalid IP" })), null);
    }

    function test_an_ip_lookup_with_no_city_still_names_the_card() {
        const hit = policy.parseIp(JSON.stringify({ latitude: 42.35, longitude: -71.06 }));
        compare(hit.label, "Here");
    }

    readonly property string forecastBody: JSON.stringify({
        current: { temperature_2m: 24.3, apparent_temperature: 25.1,
                   relative_humidity_2m: 61, wind_speed_10m: 12.4,
                   weather_code: 3, is_day: 1 },
        daily: { time: ["2026-08-03", "2026-08-04", "2026-08-05"],
                 weather_code: [3, 61, 0],
                 temperature_2m_max: [26.4, 22.1, 27.9],
                 temperature_2m_min: [18.2, 17.0, 19.4] }
    })

    function test_a_forecast_answer_becomes_a_reading_and_a_row_per_day() {
        const forecast = policy.parseForecast(forecastBody);
        compare(Math.round(forecast.current.temperature * 10), 243);
        compare(forecast.current.code, 3);
        compare(forecast.current.day, true);
        compare(forecast.days.length, 3);
        compare(forecast.days[1].date, "2026-08-04");
        compare(forecast.days[1].code, 61);
        compare(Math.round(forecast.days[1].high * 10), 221);
    }

    function test_a_forecast_with_no_temperature_is_not_a_forecast() {
        compare(policy.parseForecast(JSON.stringify({ current: { weather_code: 3 } })), null);
        compare(policy.parseForecast(JSON.stringify({ daily: { time: [] } })), null);
    }

    function test_a_forecast_with_no_daily_block_is_a_shorter_card_and_not_a_failure() {
        const forecast = policy.parseForecast(JSON.stringify({
            current: { temperature_2m: 11, weather_code: 0 }
        }));
        compare(forecast.days.length, 0);
        compare(Math.round(forecast.current.temperature), 11);
    }

    function test_a_daily_row_with_a_hole_in_it_is_dropped_and_the_rest_stay() {
        const forecast = policy.parseForecast(JSON.stringify({
            current: { temperature_2m: 11, weather_code: 0 },
            daily: { time: ["2026-08-03", "2026-08-04"],
                     weather_code: [0, 0],
                     temperature_2m_max: [20, null],
                     temperature_2m_min: [10, 9] }
        }));
        compare(forecast.days.length, 1);
        compare(forecast.days[0].date, "2026-08-03");
    }

    function test_a_night_reading_says_so_and_a_missing_flag_reads_as_day() {
        const night = policy.parseForecast(JSON.stringify({
            current: { temperature_2m: 8, weather_code: 0, is_day: 0 }
        }));
        compare(night.current.day, false);

        const unstated = policy.parseForecast(JSON.stringify({
            current: { temperature_2m: 8, weather_code: 0 }
        }));
        compare(unstated.current.day, true);
    }

    // --- what a code means ----------------------------------------------------

    function test_the_codes_this_shell_names() {
        compare(policy.conditionLabel(0), "Clear");
        compare(policy.conditionLabel(3), "Overcast");
        compare(policy.conditionLabel(48), "Fog");
        compare(policy.conditionLabel(65), "Rain");
        compare(policy.conditionLabel(67), "Freezing rain");
        compare(policy.conditionLabel(75), "Snow");
        compare(policy.conditionLabel(82), "Rain showers");
        compare(policy.conditionLabel(99), "Thunderstorm with hail");
    }

    function test_intensity_is_only_kept_where_it_changes_what_you_would_do() {
        // 61/63/65 are slight/moderate/heavy rain, and all three are "take a
        // coat". Freezing is the case that is not: 66 is the same water at a
        // temperature that closes roads.
        compare(policy.conditionLabel(61), policy.conditionLabel(65));
        verify(policy.conditionLabel(66) !== policy.conditionLabel(65));
    }

    function test_a_code_from_a_table_this_shell_does_not_have_says_so() {
        compare(policy.conditionLabel(1234), "Unknown");
        compare(policy.conditionLabel(undefined), "Unknown");
        compare(policy.conditionIcon(1234, true), "cloud-off");
    }

    function test_the_sky_itself_is_the_only_glyph_that_knows_about_night() {
        compare(policy.conditionIcon(0, true), "sun");
        compare(policy.conditionIcon(0, false), "moon");
        compare(policy.conditionIcon(1, false), "cloud-moon");
        // Rain at night is rain.
        compare(policy.conditionIcon(65, false), policy.conditionIcon(65, true));
    }

    // --- words ----------------------------------------------------------------

    function test_a_temperature_is_rounded_and_degree_signed() {
        compare(policy.temperature(24.3), "24°");
        // Just below freezing rounds to zero and is written without a sign:
        // `String(-0)` is "0" in JavaScript, and "-0°" would be a temperature
        // no thermometer displays.
        compare(policy.temperature(-0.4), "0°");
        compare(policy.temperature(-1.6), "-2°");
        compare(policy.temperature(NaN), "—");
        compare(policy.temperature(undefined), "—");
    }

    function test_wind_carries_the_unit_because_the_number_alone_says_nothing() {
        compare(policy.windLabel(12.4, "metric"), "12 km/h");
        compare(policy.windLabel(12.4, "imperial"), "12 mph");
        compare(policy.windLabel(undefined, "metric"), "");
    }

    // --- the card's two sentences ---------------------------------------------
    //
    // Both were in Surfaces/Drawers/Cards/WeatherCard.qml first, which put a
    // decision with a right answer on the far side of the seam line — the card
    // imports a Quickshell service, so `tests/` cannot reach anything left in
    // it (CLAUDE.md).

    function test_the_small_print_carries_only_what_the_service_answered() {
        compare(policy.detailLine({ feelsLike: 25.1, humidity: 61, wind: 12.4 }, "metric"),
                "feels 25° · 61% humidity · 12 km/h");
        compare(policy.detailLine({ feelsLike: 25.1, humidity: 61, wind: 12.4 }, "imperial"),
                "feels 25° · 61% humidity · 12 mph");
    }

    function test_a_missing_part_takes_its_separator_with_it() {
        // A middle dot with nothing on one side of it is worse than a shorter
        // line.
        compare(policy.detailLine({ humidity: 61 }, "metric"), "61% humidity");
        compare(policy.detailLine({ wind: 3 }, "metric"), "3 km/h");
        compare(policy.detailLine(({}), "metric"), "");
        compare(policy.detailLine(null, "metric"), "");
    }

    function test_a_card_with_no_reading_says_which_of_the_three_it_is() {
        // Three sentences and not a blank card (#81 inside a surface).
        verify(policy.emptyMessage("unset", "").indexOf("weatherTime.weather.place") > 0);
        compare(policy.emptyMessage("failed", "no such place: Bostn"), "no such place: Bostn");
        compare(policy.emptyMessage("failed", ""), "The forecast could not be read.");
        compare(policy.emptyMessage("loading", ""), "Checking the weather…");
        compare(policy.emptyMessage("idle", ""), "Checking the weather…");
    }

    function test_the_glyph_beside_it_asks_or_apologises() {
        compare(policy.emptyIcon("unset"), "map-pin");
        compare(policy.emptyIcon("loading"), "map-pin");
        compare(policy.emptyIcon("failed"), "cloud-off");
    }

    // --- one table, two readings ----------------------------------------------

    function test_a_code_has_one_row_and_both_readings_come_off_it() {
        // The word and the glyph were separate `switch`es first: one code added
        // in two places, and the day they disagree the card says "Snow" over a
        // raincloud.
        for (const code in policy.conditions) {
            const row = policy.conditions[code];
            compare(policy.conditionLabel(Number(code)), row.label);
            compare(policy.conditionIcon(Number(code), true), row.icon);
        }
    }

    function test_the_first_row_is_today_and_the_rest_are_weekdays() {
        // 2026-08-03 is a Monday.
        compare(policy.dayLabel("2026-08-03", "2026-08-03"), "Today");
        compare(policy.dayLabel("2026-08-04", "2026-08-03"), "Tue");
        compare(policy.dayLabel("2026-08-09", "2026-08-03"), "Sun");
        compare(policy.dayLabel("nonsense", "2026-08-03"), "");
    }

    function test_a_day_label_is_built_from_the_text_rather_than_from_a_date() {
        // `new Date("2026-08-03")` is midnight UTC, which in Boston is the 2nd
        // — the whole reason CalendarPolicy computes its month instead of
        // asking `Date` (#49), reappearing one card down.
        compare(policy.dayLabel("2026-08-03", "2026-01-01"), "Mon");
    }

    function test_today_is_spelled_the_way_the_api_spells_it() {
        compare(policy.isoDate(new Date(2026, 7, 3, 23, 30)), "2026-08-03");
        compare(policy.isoDate(new Date(2026, 0, 9)), "2026-01-09");
    }

    // --- the cache ------------------------------------------------------------

    readonly property var entry: policy.cacheEntry(
        "Boston", "metric",
        { label: "Boston, MA, US", latitude: 42.35, longitude: -71.06 },
        policy.parseForecast(forecastBody), 1000000)

    function test_a_cache_entry_carries_what_invalidates_it() {
        compare(entry.place, "Boston");
        compare(entry.units, "metric");
        compare(entry.fetchedAt, 1000000);
        compare(entry.days.length, 3);
    }

    function test_a_forecast_for_a_different_place_is_not_drawn_for_this_one() {
        verify(policy.usable(entry, "Boston", "metric"));
        verify(!policy.usable(entry, "Lisbon", "metric"));
    }

    function test_a_forecast_taken_in_the_other_unit_system_is_not_reused() {
        // 24 is a mild day in one system and a cold one in the other, and
        // nothing in the reading says which it was taken in.
        verify(!policy.usable(entry, "Boston", "imperial"));
    }

    function test_an_empty_cache_is_not_usable() {
        verify(!policy.usable(null, "Boston", "metric"));
        verify(!policy.usable(({}), "Boston", "metric"));
        verify(!policy.usable(policy.cacheEntry("Boston", "metric", null, null, 1), "Boston", "metric"));
    }

    function test_a_reading_goes_stale_at_the_configured_interval() {
        verify(!policy.stale(entry, 1000000 + 29 * 60000, 30));
        verify(policy.stale(entry, 1000000 + 30 * 60000, 30));
    }

    function test_a_cache_from_the_future_is_stale_rather_than_eternally_fresh() {
        // A clock corrected backwards, or a state file copied from another
        // machine: an entry stamped ahead of now would otherwise never refresh
        // again.
        verify(policy.stale(entry, 999000, 30));
    }

    function test_a_missing_cache_is_stale() {
        verify(policy.stale(null, 1000000, 30));
        verify(policy.stale(({}), 1000000, 30));
    }

    function test_a_known_place_skips_the_geocoding_call_on_the_next_start() {
        const location = policy.cachedLocation(entry, "Boston");
        compare(location.label, "Boston, MA, US");
        compare(Math.round(location.latitude * 100), 4235);
    }

    function test_a_changed_place_geocodes_again() {
        compare(policy.cachedLocation(entry, "Lisbon"), null);
        compare(policy.cachedLocation(null, "Boston"), null);
    }

    function test_the_log_line_names_the_place_and_what_it_read() {
        compare(policy.summary("Boston, MA, US", policy.parseForecast(forecastBody)),
                "Boston, MA, US 24° overcast, 3 day(s)");
        compare(policy.summary("Boston", null), "no forecast for Boston");
    }
}
