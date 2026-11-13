"""Resolve a Dutch postcode to WGS84 lat/lon via the PDOK Locatieserver.

The analysis plan (02_plan.json, schemas/plan.schema.json) selects sensors within
a radius of a centre point, so `area.lat` / `area.lon` must be filled in. Residents
give a postcode, not coordinates. The AI runs this helper when it writes the plan
to turn the postcode into a centre point. This is a geocoding lookup, not an
air-quality calculation, so it does not break the "numbers come only from R" rule.

PDOK Locatieserver is the official, free Dutch geocoder (no API key needed):
https://www.pdok.nl/restful-api/-/article/pdok-locatieserver

Postcode levels:
- PC6 (e.g. "1941 AB"): one exact point is used.
- PC4 (e.g. "1941"): the mean of the centroids of its PC6 postcodes is used, which
  gives a stable centre of the whole postcode area rather than one street.

Usage:
    python scripts/postcode_to_latlon.py 1941
    python scripts/postcode_to_latlon.py "1941 AB"
    python scripts/postcode_to_latlon.py 1941 --json

Prints "lat lon" (6 decimals) by default, or the full result as JSON with --json.
Exit code 0 = found, 1 = invalid postcode, not found, or lookup failed.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

PDOK_URL = "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free"
POSTCODE_RE = re.compile(r"^\s*([1-9][0-9]{3})\s*([A-Za-z]{2})?\s*$")
POINT_RE = re.compile(r"POINT\(([-0-9.]+)\s+([-0-9.]+)\)")
# PDOK caps "rows" at 100; large PC4 areas average the first 100 PC6 centroids.
MAX_ROWS = 100


def normalise(postcode):
    """Return ('1941', None) for a PC4 or ('1941', 'AB') for a PC6."""
    match = POSTCODE_RE.match(str(postcode))
    if not match:
        raise ValueError(
            f"'{postcode}' is not a Dutch postcode (expected 1234 or 1234 AB)"
        )
    pc4, letters = match.group(1), match.group(2)
    return pc4, letters.upper() if letters else None


def _query(params, timeout):
    url = f"{PDOK_URL}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "atai-postcode-lookup"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)["response"]["docs"]


def _centroid(doc):
    match = POINT_RE.match(doc["centroide_ll"])
    if not match:
        raise LookupError(f"unexpected centroid format: {doc['centroide_ll']}")
    lon, lat = float(match.group(1)), float(match.group(2))
    return lat, lon


def lookup(postcode, timeout=10):
    """Resolve a postcode to {postcode, name, lat, lon, source}."""
    pc4, letters = normalise(postcode)
    if letters:
        pc = f"{pc4} {letters}"
        docs = _query(
            {"q": f"postcode:{pc4}{letters}", "fq": "type:postcode",
             "fl": "weergavenaam,centroide_ll", "rows": 1},
            timeout,
        )
        if not docs:
            raise LookupError(f"no coordinates found for postcode '{pc}'")
        lat, lon = _centroid(docs[0])
        name = docs[0].get("weergavenaam", pc)
    else:
        pc = pc4
        docs = _query(
            {"q": f"postcode:{pc4}*", "fq": "type:postcode",
             "fl": "weergavenaam,centroide_ll", "rows": MAX_ROWS},
            timeout,
        )
        if not docs:
            raise LookupError(f"no coordinates found for postcode '{pc}'")
        points = [_centroid(doc) for doc in docs]
        lat = sum(point[0] for point in points) / len(points)
        lon = sum(point[1] for point in points) / len(points)
        name = f"{pc4} ({len(points)} postcodes)"
    return {
        "postcode": pc,
        "name": name,
        "lat": round(lat, 6),
        "lon": round(lon, 6),
        "source": "PDOK Locatieserver",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Resolve a Dutch postcode to WGS84 lat/lon via PDOK Locatieserver."
    )
    parser.add_argument("postcode", help="Dutch postcode, e.g. 1941 or '1941 AB'")
    parser.add_argument("--json", action="store_true",
                        help="print the full result as JSON (postcode, name, lat, lon, source)")
    args = parser.parse_args(argv)
    try:
        result = lookup(args.postcode)
    except (ValueError, LookupError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f"error: could not reach PDOK Locatieserver: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(f"{result['lat']} {result['lon']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
