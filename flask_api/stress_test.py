import requests
import concurrent.futures
import time
import os

# We hit the internal Flask port directly (bypassing Nginx for this test)
BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:5000")
ADMIN_KEY = os.environ.get("ADMIN_KEY", "dev-admin-key")
ADMIN_HEADERS = {"X-Admin-Key": ADMIN_KEY}

def run_stress_test():
    # 1. Create a fresh session
    print("--- Phase 1: Creating Instructor Session ---")
    try:
        s_res = requests.post(
            f"{BASE_URL}/session/new",
            headers=ADMIN_HEADERS,
            json={"course_name": "Cisco Stress Test"},
        )
        s_res.raise_for_status()
        session_id = s_res.json()['session_id']
        print(f"Success! Session ID: {session_id}")
    except Exception as e:
        print(f"Failed to connect to API: {e}")
        return

    # 2. Prepare 200 identical student requests
    # Using the same Roll No and Fingerprint to force a race condition
    url = f"{BASE_URL}/session/{session_id}/submit"
    payload = {
        "roll_no": "PRO2024001", 
        "fingerprint": "MOCK_HARDWARE_ID_999"
    }

    print(f"\n--- Phase 2: Unleashing 200 Concurrent Requests ---")
    start_time = time.time()

    # Using ThreadPoolExecutor to simulate 100 students hitting 'Submit' simultaneously
    with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
        # map() sends the requests in parallel
        responses = list(executor.map(lambda x: requests.post(url, json=payload), range(200)))

    duration = time.time() - start_time
    print(f"Finished in {duration:.2f} seconds.")

    # 3. Analyze the Results
    stats = {}
    for r in responses:
        stats[r.status_code] = stats.get(r.status_code, 0) + 1

    print("\n--- INFRASTRUCTURE PERFORMANCE SUMMARY ---")
    print(f"201 Created (Database Writes):    {stats.get(201, 0)}")
    print(f"409 Conflict (Redis Intercepts):  {stats.get(409, 0)}")
    print(f"500 Server Errors (Crashes):      {stats.get(500, 0)}")
    
    if stats.get(201) == 1 and stats.get(409) == 199:
        print("\nRESULT: SUCCESS. Redis shielded the DB from 199 redundant writes.")
    else:
        print("\nRESULT: CHECK LOGS. Unexpected response distribution.")

if __name__ == "__main__":
    run_stress_test()
