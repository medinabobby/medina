#!/usr/bin/env python3
"""
Generate comprehensive class instance data for District Brooklyn gym.

Creates class instances from October 2025 through December 2025 with:
- Realistic weekly schedule patterns
- Historical attendance data (past classes)
- Bobby's booking history
- Varied capacity/booking patterns

Usage: python3 Scripts/generate_class_instances.py
"""

import json
from datetime import datetime, timedelta
from pathlib import Path
import random

# Seed for reproducibility
random.seed(42)

# Load gym classes
GYM_CLASSES_PATH = Path(__file__).parent.parent / "Resources/Data/gym_classes.json"
OUTPUT_INSTANCES_PATH = Path(__file__).parent.parent / "Resources/Data/class_instances.json"
OUTPUT_BOOKINGS_PATH = Path(__file__).parent.parent / "Resources/Data/class_bookings.json"

with open(GYM_CLASSES_PATH) as f:
    gym_classes = json.load(f)

# Instructor IDs from the data
INSTRUCTORS = [
    "jazmin_scotto", "nick_vargas", "andres_riggi", "carolyn_tallents",
    "laura_lane", "anna_lee", "stevie_barbieri", "nissa_ellison_walsh",
    "lady_velez", "rachael_stark_egolf"
]

# Weekly schedule template (day of week -> list of (class_id, hour, minute, instructor_override))
# Based on a typical boutique gym schedule
WEEKLY_SCHEDULE = {
    0: [  # Monday
        ("class_full_body_burn_cellar", 6, 30, "jazmin_scotto"),
        ("class_red_light_district", 8, 0, "nick_vargas"),
        ("class_full_body_burn_cellar", 9, 0, "jazmin_scotto"),
        ("class_power_abs_express", 10, 0, "nissa_ellison_walsh"),
        ("class_lunch_break_hiit", 12, 30, "carolyn_tallents"),
        ("class_flow_flexibility", 17, 30, "jazmin_scotto"),
        ("class_build_burn_hiit", 18, 30, "nissa_ellison_walsh"),
    ],
    1: [  # Tuesday
        ("class_dynamic_morning_flow", 6, 45, "rachael_stark_egolf"),
        ("class_sweat_lab", 8, 0, "andres_riggi"),
        ("class_yoga_sculpt_burn", 9, 0, "laura_lane"),
        ("class_full_body_circuit", 10, 0, "carolyn_tallents"),
        ("class_60_plus_womens", 11, 30, "lady_velez"),
        ("class_full_body_burn", 17, 30, "jazmin_scotto"),
        ("class_level_up_power_yoga", 18, 30, "anna_lee"),
    ],
    2: [  # Wednesday
        ("class_full_body_burn_cellar", 6, 30, "jazmin_scotto"),
        ("class_red_light_district", 8, 0, "nick_vargas"),
        ("class_lit_pilates_fusion", 9, 0, "stevie_barbieri"),
        ("class_prenatal_postnatal", 10, 30, "carolyn_tallents"),
        ("class_lunch_break_hiit", 12, 30, "carolyn_tallents"),
        ("class_flow_flexibility", 17, 30, "jazmin_scotto"),
        ("class_glutes_abs", 18, 30, "andres_riggi"),
    ],
    3: [  # Thursday
        ("class_dynamic_morning_flow", 6, 45, "rachael_stark_egolf"),
        ("class_full_body_burn", 8, 0, "jazmin_scotto"),
        ("class_yoga_sculpt_burn", 9, 0, "laura_lane"),
        ("class_power_abs_express", 10, 0, "nissa_ellison_walsh"),
        ("class_full_body_circuit", 17, 30, "carolyn_tallents"),
        ("class_all_level_flow_yoga", 18, 30, "anna_lee"),
        ("class_build_burn_hiit", 19, 0, "nissa_ellison_walsh"),
    ],
    4: [  # Friday
        ("class_full_body_burn_cellar", 6, 30, "jazmin_scotto"),
        ("class_red_light_district", 8, 0, "nick_vargas"),
        ("class_full_body_burn_cellar", 9, 0, "jazmin_scotto"),
        ("class_power_abs_express", 10, 0, "nissa_ellison_walsh"),
        ("class_prenatal_postnatal", 10, 30, "carolyn_tallents"),
        ("class_full_body_burn", 17, 30, "jazmin_scotto"),
    ],
    5: [  # Saturday
        ("class_lit_pilates_fusion", 8, 0, "stevie_barbieri"),
        ("class_all_level_flow_yoga", 9, 0, "anna_lee"),
        ("class_full_body_burn_cellar", 10, 0, "jazmin_scotto"),
        ("class_red_light_district", 11, 0, "nick_vargas"),
        ("class_glutes_abs", 12, 0, "andres_riggi"),
    ],
    6: [  # Sunday
        ("class_lit_pilates_fusion", 8, 0, "stevie_barbieri"),
        ("class_level_up_power_yoga", 9, 0, "anna_lee"),
        ("class_red_light_district", 10, 0, "nick_vargas"),
        ("class_full_body_burn_cellar", 10, 0, "jazmin_scotto"),
        ("class_flow_flexibility", 11, 0, "jazmin_scotto"),
        ("class_yin_yoga_glow", 16, 0, "anna_lee"),
    ],
}

# Bobby's favorite classes (more likely to book)
BOBBY_FAVORITES = [
    "class_full_body_burn_cellar",
    "class_red_light_district",
    "class_build_burn_hiit",
    "class_sweat_lab",
]

def generate_instance_id(class_id: str, dt: datetime) -> str:
    """Generate a unique instance ID."""
    prefix = class_id.replace("class_", "")[:12]
    date_str = dt.strftime("%Y%m%d_%H%M")
    return f"instance_{prefix}_{date_str}"

def generate_booking_id(member_id: str, class_id: str, dt: datetime) -> str:
    """Generate a unique booking ID."""
    prefix = class_id.replace("class_", "")[:10]
    date_str = dt.strftime("%Y%m%d")
    return f"booking_{member_id}_{prefix}_{date_str}"

def get_booking_pattern(dt: datetime, class_id: str, gym_class: dict) -> tuple:
    """
    Generate realistic booking patterns.
    Returns (booked_count, waitlist_count)
    """
    capacity = gym_class.get("capacity", 20)
    is_past = dt < datetime.now()
    is_weekend = dt.weekday() >= 5
    is_morning = dt.hour < 10
    is_popular = class_id in BOBBY_FAVORITES

    # Base booking rate
    if is_past:
        # Past classes were attended
        base_rate = random.uniform(0.6, 0.95)
    elif is_weekend:
        base_rate = random.uniform(0.5, 0.85)
    elif is_morning:
        base_rate = random.uniform(0.4, 0.8)
    else:
        base_rate = random.uniform(0.3, 0.7)

    if is_popular:
        base_rate = min(1.0, base_rate + 0.15)

    booked = int(capacity * base_rate)

    # Add waitlist for full classes
    waitlist = 0
    if booked >= capacity:
        booked = capacity
        if random.random() < 0.3:
            waitlist = random.randint(1, 4)

    return booked, waitlist

def should_bobby_book(dt: datetime, class_id: str, day_classes: list) -> bool:
    """
    Determine if Bobby should book this class.
    Bobby books ~2-3 classes per week, preferring his favorites.
    """
    is_favorite = class_id in BOBBY_FAVORITES
    is_past = dt < datetime.now()

    # Past: Bobby attended ~2.5 classes/week on average
    # Future: Bobby has some upcoming bookings

    # Simple heuristic: book favorites more, ~25% chance for favorites
    if is_favorite:
        return random.random() < 0.25
    else:
        return random.random() < 0.08

def generate_class_instances():
    """Generate all class instances from Oct 2025 through Dec 2025."""
    instances = {}
    bookings = {}

    # Date range: Oct 1, 2025 to Dec 31, 2025
    start_date = datetime(2025, 10, 1)
    end_date = datetime(2025, 12, 31)
    now = datetime.now()

    current_date = start_date
    bobby_weekly_bookings = {}  # Track Bobby's bookings per week

    while current_date <= end_date:
        day_of_week = current_date.weekday()
        schedule = WEEKLY_SCHEDULE.get(day_of_week, [])
        week_key = current_date.strftime("%Y-W%W")

        day_classes = []

        for class_id, hour, minute, instructor in schedule:
            if class_id not in gym_classes:
                continue

            gym_class = gym_classes[class_id]
            dt = current_date.replace(hour=hour, minute=minute, second=0, microsecond=0)
            instance_id = generate_instance_id(class_id, dt)

            booked_count, waitlist_count = get_booking_pattern(dt, class_id, gym_class)
            is_past = dt < now

            status = "completed" if is_past else "scheduled"

            instance = {
                "id": instance_id,
                "gymClassId": class_id,
                "gymId": "district_brooklyn",
                "scheduledDate": dt.strftime("%Y-%m-%dT%H:%M:%S-05:00"),
                "instructorId": instructor,
                "locationName": gym_class.get("locationName", "Class Studio + Spa"),
                "capacity": gym_class.get("capacity", 20),
                "bookedCount": booked_count,
                "waitlistCount": waitlist_count,
                "status": status,
                "address": gym_class.get("address", "389 Court St")
            }

            instances[instance_id] = instance
            day_classes.append((instance_id, class_id, dt))

        # Generate Bobby's bookings for this day
        bobby_week_count = bobby_weekly_bookings.get(week_key, 0)

        for instance_id, class_id, dt in day_classes:
            # Bobby books 2-3 classes per week
            if bobby_week_count >= 3:
                break

            if should_bobby_book(dt, class_id, day_classes):
                is_past = dt < now
                booking_id = generate_booking_id("bobby", class_id, dt)

                # Booking source varies
                source = random.choice(["app", "app", "app", "ai"])

                booking = {
                    "id": booking_id,
                    "memberId": "bobby",
                    "classInstanceId": instance_id,
                    "gymClassId": class_id,
                    "gymId": "district_brooklyn",
                    "status": "attended" if is_past else "confirmed",  # v112.2: Use 'attended' not 'completed'
                    "waitlistPosition": None,
                    "creditUsed": 1,
                    "bookedAt": (dt - timedelta(days=random.randint(1, 7))).strftime("%Y-%m-%dT%H:%M:%S-05:00"),
                    "cancelledAt": None,
                    "checkedInAt": dt.strftime("%Y-%m-%dT%H:%M:%S-05:00") if is_past else None,
                    "bookingSource": source
                }

                bookings[booking_id] = booking
                bobby_week_count += 1
                bobby_weekly_bookings[week_key] = bobby_week_count

        current_date += timedelta(days=1)

    return instances, bookings

def main():
    print("Generating class instances...")
    instances, bookings = generate_class_instances()

    print(f"Generated {len(instances)} class instances")
    print(f"Generated {len(bookings)} Bobby bookings")

    # Count by month
    months = {}
    for inst in instances.values():
        month = inst["scheduledDate"][:7]
        months[month] = months.get(month, 0) + 1

    print("\nInstances by month:")
    for month in sorted(months.keys()):
        print(f"  {month}: {months[month]} classes")

    # Count Bobby bookings
    past_bookings = sum(1 for b in bookings.values() if b["status"] == "attended")
    future_bookings = sum(1 for b in bookings.values() if b["status"] == "confirmed")
    print(f"\nBobby's bookings: {past_bookings} past, {future_bookings} upcoming")

    # Save to files
    with open(OUTPUT_INSTANCES_PATH, "w") as f:
        json.dump(instances, f, indent=2)
    print(f"\nSaved instances to {OUTPUT_INSTANCES_PATH}")

    with open(OUTPUT_BOOKINGS_PATH, "w") as f:
        json.dump(bookings, f, indent=2)
    print(f"Saved bookings to {OUTPUT_BOOKINGS_PATH}")

if __name__ == "__main__":
    main()
