import json
import urllib.request
import math
import os
import time

def deg2num(lat_deg, lon_deg, zoom):
  lat_rad = math.radians(lat_deg)
  n = 2.0 ** zoom
  xtile = int((lon_deg + 180.0) / 360.0 * n)
  ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
  return (xtile, ytile)

def download_tiles():
    # Bounds for Shivalik College of Engineering roughly
    min_lat, max_lat = 30.3480, 30.3580
    min_lng, max_lng = 77.8950, 77.9050
    zoom = 17

    min_x, max_y = deg2num(min_lat, min_lng, zoom)
    max_x, min_y = deg2num(max_lat, max_lng, zoom)

    print(f"Downloading map tiles for zoom {zoom}...")
    count = 0
    for x in range(min_x, max_x + 1):
        for y in range(min_y, max_y + 1):
            url = f"https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={zoom}"
            path = f"assets/offline_tiles/{zoom}/{x}"
            os.makedirs(path, exist_ok=True)
            file_path = f"{path}/{y}.png"
            if not os.path.exists(file_path):
                try:
                    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req) as response, open(file_path, 'wb') as out_file:
                        out_file.write(response.read())
                    count += 1
                    time.sleep(0.1) # Be polite
                except Exception as e:
                    print(f"Failed to download tile {x}/{y}: {e}")
    print(f"✅ Downloaded {count} high-res offline map tiles!")

def fetch_osrm_curve(start, end):
    url = f"http://router.project-osrm.org/route/v1/foot/{start['lng']},{start['lat']};{end['lng']},{end['lat']}?overview=full&geometries=geojson"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            coords = data['routes'][0]['geometry']['coordinates']
            # OSRM returns [lon, lat], we want [lat, lon] for Flutter
            return [{"lat": c[1], "lng": c[0]} for c in coords]
    except Exception as e:
        print(f"Failed OSRM {start['id']} to {end['id']}: {e}")
        return []

def update_trail_graph():
    print("Updating offline routing graph with real real-world curves...")
    with open("assets/trail_graph.json", "r") as f:
        graph = json.load(f)

    node_map = {n["id"]: n for n in graph["nodes"]}

    for edge in graph["edges"]:
        n1 = node_map[edge["from"]]
        n2 = node_map[edge["to"]]
        print(f"Fetching physical geometry for {n1['id']} -> {n2['id']}...")
        curve = fetch_osrm_curve(n1, n2)
        if curve:
            edge["offline_path"] = curve
        time.sleep(1) # Be polite to OSRM API

    with open("assets/trail_graph.json", "w") as f:
        json.dump(graph, f, indent=2)
    print("✅ Offline routing graph upgraded with physical curves!")

if __name__ == "__main__":
    download_tiles()
    update_trail_graph()
    print("\n🎉 DONE! Run your flutter app offline now, it will look exactly like online!")
