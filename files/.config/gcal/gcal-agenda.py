#!/usr/bin/env python3
"""Fetch upcoming events from Google Calendar iCal URLs.

Reads secret iCal URLs from ~/.config/gcal/calendars (one URL per line,
blank lines and #comments ignored). Prints upcoming events for today
and tomorrow by default.

Usage:
    gcal-agenda            # today + tomorrow
    gcal-agenda 7          # next 7 days
    gcal-agenda --json     # JSON output (for waybar/conky)
"""

import sys
import os
import json
import urllib.request
from datetime import datetime, timedelta, date

from icalendar import Calendar
import recurring_ical_events

CALENDARS_FILE = os.path.expanduser("~/.config/gcal/calendars")


def load_urls():
    if not os.path.exists(CALENDARS_FILE):
        print(f"No calendars configured. Add iCal URLs to {CALENDARS_FILE}", file=sys.stderr)
        print(f"(Google Calendar → Settings → calendar → 'Secret address in iCal format')", file=sys.stderr)
        sys.exit(1)

    urls = []
    with open(CALENDARS_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)
    return urls


def fetch_events(urls, cutoff_date):
    now = datetime.now().astimezone()
    today = now.date()
    events = []

    for url in urls:
        try:
            resp = urllib.request.urlopen(url, timeout=10)
            cal = Calendar.from_ical(resp.read())
        except Exception as e:
            print(f"Error fetching calendar: {e}", file=sys.stderr)
            continue

        # Extract calendar owner email for filtering declined events
        calendar_owner = str(cal.get("X-WR-CALNAME", "")).lower()

        # Expand recurring events into individual occurrences
        expanded = recurring_ical_events.of(cal).between(today, cutoff_date)

        for component in expanded:
            # Skip events we declined
            attendees = component.get("attendee", [])
            if not isinstance(attendees, list):
                attendees = [attendees]
            declined = False
            for attendee in attendees:
                if not hasattr(attendee, "params"):
                    continue
                email = str(attendee).replace("mailto:", "").lower()
                partstat = str(attendee.params.get("PARTSTAT", ""))
                if email == calendar_owner and partstat == "DECLINED":
                    declined = True
                    break
            if declined:
                continue

            dtstart = component.get("dtstart")
            if dtstart is None:
                continue
            dt = dtstart.dt

            # Handle all-day events (date) vs timed events (datetime)
            if isinstance(dt, date) and not isinstance(dt, datetime):
                event_date = dt
                event_dt = datetime(dt.year, dt.month, dt.day).astimezone()
                all_day = True
                end_time = ""
            else:
                if dt.tzinfo is None:
                    dt = dt.astimezone()
                event_date = dt.date()
                event_dt = dt
                all_day = False
                dtend = component.get("dtend")
                if dtend and isinstance(dtend.dt, datetime):
                    end_dt = dtend.dt
                    if end_dt.tzinfo is None:
                        end_dt = end_dt.astimezone()
                    end_time = end_dt.strftime("%H:%M")
                else:
                    end_time = ""

            summary = str(component.get("summary", "No title"))
            events.append({
                "summary": summary,
                "start": event_dt.isoformat(),
                "date": event_date.isoformat(),
                "all_day": all_day,
                "time": "All day" if all_day else event_dt.strftime("%H:%M"),
                "end_time": end_time,
            })

    events.sort(key=lambda e: e["start"])
    return events


def format_text(events):
    if not events:
        return "No upcoming events"

    lines = []
    current_date = None
    for ev in events:
        if ev["date"] != current_date:
            current_date = ev["date"]
            d = date.fromisoformat(current_date)
            header = d.strftime("%a %b %d")
            if d == date.today():
                header = f"Today ({header})"
            elif d == date.today() + timedelta(days=1):
                header = f"Tomorrow ({header})"
            lines.append(f"\033[1;35m{header}\033[0m")

        if ev["end_time"]:
            time_str = f"\033[36m{ev['time']}-{ev['end_time']}\033[0m"
        else:
            time_str = f"\033[36m{ev['time']:>7}\033[0m"
        lines.append(f"  {time_str}  {ev['summary']}")

    return "\n".join(lines)


def days_to_cutoff(days):
    return date.today() + timedelta(days=days)


def end_of_business_week():
    """Return Friday of the current week (or today if past Friday)."""
    today = date.today()
    weekday = today.weekday()  # Mon=0 ... Fri=4
    if weekday <= 4:
        return today + timedelta(days=4 - weekday)
    else:
        # Weekend — show next Friday
        return today + timedelta(days=11 - weekday)


def main():
    cutoff = days_to_cutoff(2)
    as_json = False

    for arg in sys.argv[1:]:
        if arg == "--json":
            as_json = True
        elif arg == "--week":
            cutoff = end_of_business_week()
        elif arg.isdigit():
            cutoff = days_to_cutoff(int(arg))

    urls = load_urls()
    events = fetch_events(urls, cutoff)

    if as_json:
        # For waybar: bar shows next 2 events, tooltip shows full week
        week_cutoff = end_of_business_week()
        week_events = fetch_events(urls, week_cutoff) if cutoff != week_cutoff else events

        if events:
            # Bar text: next upcoming event (skip past ones)
            now = datetime.now().astimezone()
            upcoming = [e for e in events if not e["all_day"] and datetime.fromisoformat(e["start"]) > now]
            if not upcoming:
                upcoming = [e for e in events if e["all_day"] and date.fromisoformat(e["date"]) >= date.today()]
            next_ev = upcoming[0] if upcoming else events[0]
            d = date.fromisoformat(next_ev["date"])
            day_label = d.strftime("%a")
            text = f"󰃭 {day_label} {next_ev['time']}"

            # Tooltip: full week grouped by day with Pango colors
            tip_lines = []
            current_date = None
            for ev in week_events:
                if ev["date"] != current_date:
                    current_date = ev["date"]
                    d = date.fromisoformat(current_date)
                    header = d.strftime("%a %b %d")
                    if d == date.today():
                        header = f"Today ({header})"
                    elif d == date.today() + timedelta(days=1):
                        header = f"Tomorrow ({header})"
                    if tip_lines:
                        tip_lines.append("")
                    tip_lines.append(f"<b><span color='#bd93f9'>{header}</span></b>")
                if ev["end_time"]:
                    time_str = f"<span color='#8be9fd'>{ev['time']}-{ev['end_time']}</span>"
                else:
                    time_str = f"<span color='#8be9fd'>{ev['time']:>7}</span>"
                tip_lines.append(f"  {time_str}  {ev['summary']}")

            print(json.dumps({
                "text": text,
                "tooltip": "\n".join(tip_lines),
                "class": "has-events",
            }))
        else:
            print(json.dumps({"text": "󰃭 No events", "tooltip": "", "class": "no-events"}))
    else:
        print(format_text(events))


if __name__ == "__main__":
    main()
