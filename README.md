# Course Attendance System

A lightweight, secure, and extensible web-based attendance system built using Flask. The system leverages device fingerprinting and geolocation-based validation to ensure authenticity and prevent duplicate submissions.

---

## Overview

This system enables students to mark attendance through a web interface while enforcing:

- Device-level uniqueness using browser fingerprinting  
- Location-based validation via geofencing  
- Daily attendance isolation using date-partitioned CSV storage  

---

## System Design

### Core Components

| Component | Role |
|----------|------|
| Frontend (HTML + JavaScript) | Captures user input, device fingerprint, and location |
| FingerprintJS | Generates a unique device identifier |
| Flask Backend | Validates submissions and stores data |
| CSV Storage | Maintains daily attendance logs |
| Geopy | Computes distance for geofencing |

---

## Features

### 1. Device-Based Duplicate Prevention
- Each submission includes a fingerprint ID  
- Prevents multiple submissions from the same device in a day  

---

### 2. Geofencing (Optional)
- Ensures users are physically present near a predefined location  
- Uses latitude/longitude with a configurable radius constraint  

---

### 3. Daily Partitioned Storage
- Attendance stored as:
```
IML-YYYY-MM-DD.csv
```
- Ensures clean separation of records per day  

---

### 4. Structured Logging

Each record contains the following fields:

| Field | Description |
|------|-------------|
| Timestamp | Submission time |
| Name | Student name |
| RollNo | Student roll number |
| Comments | Optional input |
| Latitude | User location |
| Longitude | User location |
| Fingerprint | Device identifier |

---

## Project Structure
```
.
├── main.py # Flask application
├── config.json # System configuration
├── templates/
│ ├── index.html # Attendance form
│ ├── thank_you.html # Success page
│ └── denied.html # Duplicate submission page
├── static/ # Optional static assets
└── IML-YYYY-MM-DD.csv # Daily attendance logs
```

---

## Installation and Setup

### 1. Clone Repository
```bash
git clone <repo-url>
cd attendance-system
```

### 2. Install Dependencies
```
pip install flask geopy
```

---

### 3. Configure System

Edit `config.json`:

```
{
  "GEOFENCING_ENABLED": true,
  "COURSE_LOCATION_LAT": 0.0,
  "COURSE_LOCATION_LON": 0.0,
  "ALLOWED_RADIUS_METERS": 500,
  "CSV_PREFIX": "IML"
}
```

---

### 4. Run Server

```
python main.py
```

The server runs on:
```
http://localhost:8080
```

---

## Usage Flow

1. User opens the attendance page  
2. User enters:
   - Name  
   - Roll Number  
   - Comments (optional)  
3. System:
   - Generates a device fingerprint  
   - Requests location access  
4. Backend validates:
   - Geolocation (if enabled)  
   - Duplicate submission (fingerprint)  
5. Result:
   - Success → redirected to /thank-you  
   - Duplicate → redirected to /denied  

---

## Validation Logic

### Step 1: Geofence Check
```
distance(user_location, course_location) <= allowed_radius
```

### Step 2: Duplicate Check
```
fingerprint not present in today's CSV
```

---

## Limitations

- Fingerprinting is probabilistic and not guaranteed to be unique  
- Shared devices may block valid users  
- Multiple devices can bypass duplicate detection  
- CSV storage is not concurrency-safe for high-scale usage  

---

## Design Assumptions

<assumption> Each device corresponds to a single student per session </assumption>  
<assumption> Students are physically present within the geofence </assumption>  
<assumption> The system operates under low concurrency </assumption>  

---

## Possible Improvements

### Identity-Based Validation
- Enforce uniqueness using roll number instead of fingerprint  

### Database Integration
- Replace CSV with SQLite or PostgreSQL  

### Analytics Layer
- Track attendance trends  
- Detect late submissions  

### Anomaly Detection
- Identify multiple roll numbers from the same fingerprint  
- Detect repeated submissions from the same IP  

### Security Enhancements
- Hash fingerprint values server-side  
- Introduce token-based session validation  

---

## Testing Scenarios

| Scenario | Expected Outcome |
|---------|----------------|
| Same device, multiple attempts | Denied |
| Different device, same user | Allowed |
| Outside geofence | Denied |
| First valid submission | Accepted |

---

## Key Insight

The system enforces device-level uniqueness rather than user-level identity. The fingerprint acts as a proxy for device identity, not a definitive representation of a user.
