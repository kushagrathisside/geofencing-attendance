# main.py

import csv
import os
import json
from datetime import datetime, date as dt_date
from flask import Flask, render_template, request, redirect, url_for
from geopy.distance import geodesic

# --- Load Configuration from config.json ---
with open('config.json', 'r') as f:
    config = json.load(f)

app = Flask(__name__)

def get_daily_csv_filename():
    """Generates the CSV filename for the current day, e.g., 'IML-2025-08-11.csv'."""
    prefix = config.get("CSV_PREFIX", "attendance")
    today_str = dt_date.today().isoformat()
    return f"{prefix}-{today_str}.csv"

def initialize_csv(filename):
    """Creates the daily CSV file with a header if it doesn't exist."""
    if not os.path.exists(filename):
        header = ['Timestamp', 'Name', 'RollNo', 'Comments', 'Latitude', 'Longitude', 'Fingerprint']
        with open(filename, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(header)

def is_daily_duplicate(fingerprint, filename):
    """Checks the daily CSV file for a duplicate fingerprint."""
    if not os.path.exists(filename):
        return False
    with open(filename, 'r', newline='') as f:
        reader = csv.reader(f)
        next(reader)  # Skip header
        for row in reader:
            # Fingerprint is now the last column (index 6)
            if len(row) > 6 and row[6] == fingerprint:
                return True
    return False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/thank-you')
def thank_you():
    return render_template('thank_you.html')

@app.route('/denied')
def denied():
    return render_template('denied.html')

@app.route('/submit', methods=['POST'])
def submit():
    try:
        daily_filename = get_daily_csv_filename()
        initialize_csv(daily_filename)
        
        fingerprint = request.form['fingerprint']
        latitude = float(request.form['latitude'])
        longitude = float(request.form['longitude'])

        # --- 1. Geofence Validation (Optional) ---
        if config.get("GEOFENCING_ENABLED", False):
            course_location = (config["COURSE_LOCATION_LAT"], config["COURSE_LOCATION_LON"])
            allowed_radius = config["ALLOWED_RADIUS_METERS"]
            submitted_location = (latitude, longitude)
            distance = geodesic(course_location, submitted_location).meters
            if distance > allowed_radius:
                return f"<h1>Submission Denied</h1><p>You must be within {allowed_radius} meters of the course location.</p>", 403

        # --- 2. Daily Duplicate Check ---
        if is_daily_duplicate(fingerprint, daily_filename):
            return redirect(url_for('denied'))

        # --- 3. Save Data to Daily CSV File ---
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        name = request.form['name']
        roll_no = request.form['roll_no']
        comments = request.form['comments']

        with open(daily_filename, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([timestamp, name, roll_no, comments, latitude, longitude, fingerprint])
        
        return redirect(url_for('thank_you'))

    except Exception as e:
        print(f"An error occurred: {e}")
        return "<h1>An error occurred</h1><p>Could not process your submission.</p>", 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
