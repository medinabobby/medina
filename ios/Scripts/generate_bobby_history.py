#!/usr/bin/env python3
"""
Generate Bobby's 15-month training history with realistic performance data.

v102: Rich historical data with actual performance (hit/exceed/struggle/skip patterns)
      Generates: plans, programs, workouts, instances, sets with actuals

v114: 3 programs per plan with periodization phases:
      - Accumulation (weeks 1-4): 60%→70% intensity, volume focus
      - Intensification (weeks 5-8): 70%→80% intensity, strength focus
      - Realization (weeks 9-12): 80%→90% intensity, peaking

Based on 1RM progression data from Oct 2024 to Dec 2025.
"""

import json
import random
from datetime import datetime, timedelta

# Use deterministic seed for reproducible data
random.seed(42)

# 1RM progression data (at START of each quarter)
QUARTERS = [
    {"name": "Q4 2024", "start": "2024-10-01", "end": "2024-12-31", "bodyweight": 144},
    {"name": "Q1 2025", "start": "2025-01-01", "end": "2025-03-31", "bodyweight": 148},
    {"name": "Q2 2025", "start": "2025-04-01", "end": "2025-06-30", "bodyweight": 152},
    {"name": "Q3 2025", "start": "2025-07-01", "end": "2025-09-30", "bodyweight": 149},
    {"name": "Q4 2025", "start": "2025-10-01", "end": "2025-12-31", "bodyweight": 150},
]

# 1RM values at start of each quarter
ONE_RM_PROGRESSION = {
    "barbell_back_squat": [170, 180, 215, 220, 195],
    "conventional_deadlift": [130, 155, 200, 240, 260],
    "barbell_bench_press": [135, 165, 185, 200, 195],
    "overhead_press": [60, 80, 100, 105, 100],
    "pull_up": [144, 168, 192, 214, 215],  # BW + added weight
    "pendlay_row": [75, 105, 135, 150, 125],
    # Secondary exercises (estimated from main lifts)
    "dumbbell_bench_press": [50, 60, 70, 75, 70],  # per hand
    "barbell_row": [95, 115, 140, 155, 130],
    "lat_pulldown": [100, 120, 140, 150, 145],
    "dumbbell_lateral_raise": [15, 20, 25, 27, 25],  # per hand
    "tricep_extension": [40, 50, 60, 65, 60],
    "barbell_curl": [50, 60, 75, 80, 75],
}

# Full body workout template: 5 exercises per workout
FULL_BODY_EXERCISES = [
    # Primary compound
    ["barbell_back_squat", "conventional_deadlift"],  # Alternate
    # Upper push
    ["barbell_bench_press", "overhead_press"],  # Alternate
    # Upper pull
    ["pull_up", "barbell_row", "lat_pulldown"],
    # Accessory 1
    ["dumbbell_lateral_raise", "tricep_extension"],
    # Accessory 2
    ["barbell_curl", "pendlay_row"],
]

# Protocol templates - IDs must match protocol_configs.json
PROTOCOLS = {
    "strength_3x5_moderate": {"reps": [5, 5, 5], "intensity": 0.75, "rest": 180},
    "strength_5x5_straight": {"reps": [5, 5, 5, 5, 5], "intensity": 0.70, "rest": 180},
    "strength_3x8_moderate": {"reps": [8, 8, 8], "intensity": 0.65, "rest": 90},
    "strength_3x10_moderate": {"reps": [10, 10, 10], "intensity": 0.60, "rest": 90},
    "strength_3x12_light": {"reps": [12, 12, 12], "intensity": 0.55, "rest": 60},
}

# v114: Periodization phases for each quarterly plan
# TrainingFocus enum values: foundation, development, peak, maintenance, deload
# Protocol IDs must match protocol_configs.json
PHASES = [
    {
        "name": "Accumulation",
        "weeks": (1, 4),
        "intensity_range": (0.60, 0.70),
        "protocol": "strength_3x10_moderate",  # 3x10 volume work
        "focus": "foundation",  # Build work capacity
        "rationale": "Build work capacity with moderate intensity, higher volume"
    },
    {
        "name": "Intensification",
        "weeks": (5, 8),
        "intensity_range": (0.70, 0.80),
        "protocol": "strength_5x5_straight",  # 5x5 strength work
        "focus": "development",  # Strength development
        "rationale": "Increase intensity, reduce volume for strength adaptation"
    },
    {
        "name": "Realization",
        "weeks": (9, 12),
        "intensity_range": (0.80, 0.90),
        "protocol": "strength_3x5_moderate",  # 3x5 peaking
        "focus": "peak",  # Peaking phase
        "rationale": "Peak strength with high intensity, low volume"
    },
]


def get_1rm_for_date(exercise_id, workout_date):
    """Get the 1RM value for an exercise at a given date."""
    if exercise_id not in ONE_RM_PROGRESSION:
        return 100  # Default for unknown exercises

    values = ONE_RM_PROGRESSION[exercise_id]

    # Find which quarter this date falls into
    for i, q in enumerate(QUARTERS):
        start = datetime.strptime(q["start"], "%Y-%m-%d").date()
        end = datetime.strptime(q["end"], "%Y-%m-%d").date()
        if start <= workout_date <= end:
            return values[i] if i < len(values) else values[-1]

    return values[-1]  # Default to latest


def generate_actual_performance(target_weight, target_reps, workout_date, exercise_num):
    """Generate realistic actual performance based on target.

    Returns: (actual_weight, actual_reps, completion_status)
    """
    # Use workout date + exercise position for deterministic randomness
    seed_val = hash(f"{workout_date}_{exercise_num}")
    random.seed(seed_val)

    outcome = random.choices(
        ["hit", "exceeded", "struggled", "weight_drop", "skipped"],
        weights=[60, 15, 15, 5, 5]
    )[0]

    if outcome == "hit":
        return target_weight, target_reps, "completed"
    elif outcome == "exceeded":
        extra_reps = random.randint(1, 3)
        return target_weight, target_reps + extra_reps, "completed"
    elif outcome == "struggled":
        max_fewer = max(1, min(2, target_reps - 1))
        fewer_reps = random.randint(1, max_fewer) if max_fewer > 0 else 1
        return target_weight, max(1, target_reps - fewer_reps), "completed"
    elif outcome == "weight_drop":
        # Dropped weight by 10%, hit target reps
        return round(target_weight * 0.9, 1), target_reps, "completed"
    else:
        return None, None, "skipped"


def should_skip_workout(workout_date):
    """Determine if entire workout should be skipped (~10% rate)."""
    random.seed(hash(str(workout_date)))
    return random.random() < 0.10


def should_skip_exercise(workout_date, exercise_num):
    """Determine if an exercise should be skipped (~5% rate)."""
    random.seed(hash(f"{workout_date}_ex_{exercise_num}"))
    return random.random() < 0.05


def select_exercises_for_workout(workout_date, workout_type):
    """Select 5 exercises for a full body workout, alternating patterns."""
    if workout_type == "cardio":
        return ["treadmill_run"]  # Single cardio exercise

    exercises = []
    day_num = workout_date.toordinal()  # Use date for alternation

    for i, group in enumerate(FULL_BODY_EXERCISES):
        # Rotate through options based on day
        choice = group[(day_num + i) % len(group)]
        exercises.append(choice)

    return exercises


def generate_plans():
    """Generate 5 quarterly plans for Bobby."""
    plans = {}

    for i, q in enumerate(QUARTERS):
        plan_id = f"plan_bobby_{q['name'].lower().replace(' ', '_')}"
        status = "active" if i == 4 else "completed"

        plans[plan_id] = {
            "id": plan_id,
            "name": f"{q['name']} Strength",
            "description": f"Quarterly strength program {q['name']}",
            "goal": "strength",
            "memberId": "bobby",
            "trainerId": "nick_vargas",
            "startDate": f"{q['start']}T00:00:00Z",
            "endDate": f"{q['end']}T23:59:59Z",
            "status": status,
            "splitType": "full_body",
            "preferredDays": ["monday", "tuesday", "wednesday", "thursday", "friday"],
            "compoundTimeAllocation": 0.6,
            "isolationApproach": "volume_accumulation",
            "emphasizedMuscleGroups": [],
            "excludedMuscleGroups": [],
            "targetSessionDuration": 45,
            "trainingLocation": "gym",
            "cardioDays": 2,
            "weightliftingDays": 3,
            "isSingleWorkout": False,
            "experienceLevel": "intermediate",
        }

    return plans


def generate_programs():
    """Generate 3 programs per quarterly plan (15 total).

    v114: Each plan has 3 phases:
    - Accumulation (weeks 1-4): volume focus
    - Intensification (weeks 5-8): strength focus
    - Realization (weeks 9-12): peaking
    """
    programs = {}
    today = datetime.now().date()

    for i, q in enumerate(QUARTERS):
        quarter_id = q["name"].lower().replace(" ", "_")
        plan_id = f"plan_bobby_{quarter_id}"
        quarter_start = datetime.strptime(q["start"], "%Y-%m-%d").date()
        quarter_end = datetime.strptime(q["end"], "%Y-%m-%d").date()

        for phase_idx, phase in enumerate(PHASES):
            prog_id = f"prog_bobby_{quarter_id}_{phase['name'].lower()}"

            # Calculate phase dates (roughly 4 weeks each)
            week_start, week_end = phase["weeks"]
            phase_start = quarter_start + timedelta(weeks=week_start - 1)
            phase_end = min(quarter_start + timedelta(weeks=week_end) - timedelta(days=1), quarter_end)

            # Determine status based on dates and today
            if phase_end < today:
                status = "completed"
            elif phase_start <= today <= phase_end:
                status = "active"
            else:
                status = "scheduled"

            # For current quarter (Q4 2025), override: only Realization is active
            if i == 4:  # Q4 2025
                if phase_idx == 2:  # Realization
                    status = "active"
                elif phase_idx < 2:  # Earlier phases
                    status = "completed"

            programs[prog_id] = {
                "id": prog_id,
                "planId": plan_id,
                "name": phase["name"],
                "focus": phase["focus"],
                "status": status,
                "startDate": f"{phase_start.isoformat()}T00:00:00Z",
                "endDate": f"{phase_end.isoformat()}T23:59:59Z",
                "startingIntensity": phase["intensity_range"][0],
                "endingIntensity": phase["intensity_range"][1],
                "progressionType": "linear",
                "rationale": phase["rationale"],
            }

    return programs


def get_phase_for_week(week_num):
    """Determine which phase (program) a week belongs to.

    v114: Returns phase index and phase data based on week number.
    """
    for idx, phase in enumerate(PHASES):
        week_start, week_end = phase["weeks"]
        if week_start <= week_num <= week_end:
            return idx, phase
    # Default to last phase for weeks beyond 12
    return 2, PHASES[2]


def get_intensity_for_week(week_num, phase):
    """Calculate intensity for a given week within a phase.

    v114: Linear interpolation from start to end intensity within the phase.
    """
    week_start, week_end = phase["weeks"]
    intensity_start, intensity_end = phase["intensity_range"]

    # Calculate progress through the phase (0.0 to 1.0)
    phase_weeks = week_end - week_start + 1
    week_in_phase = week_num - week_start
    progress = week_in_phase / max(1, phase_weeks - 1) if phase_weeks > 1 else 0

    # Linear interpolation
    return intensity_start + (intensity_end - intensity_start) * progress


def generate_workouts_with_data():
    """Generate workouts, instances, and sets with realistic performance data.

    v114: Now assigns workouts to correct program based on week number:
    - Weeks 1-4: Accumulation
    - Weeks 5-8: Intensification
    - Weeks 9-12: Realization
    """
    workouts = []
    instances = {}
    sets = {}
    today = datetime.now().date()

    total_stats = {
        "workouts_completed": 0,
        "workouts_skipped": 0,
        "exercises_completed": 0,
        "exercises_skipped": 0,
        "sets_completed": 0,
        "sets_skipped": 0,
    }

    for i, q in enumerate(QUARTERS):
        quarter_id = q["name"].lower().replace(" ", "_")

        start_date = datetime.strptime(q["start"], "%Y-%m-%d").date()
        end_date = datetime.strptime(q["end"], "%Y-%m-%d").date()

        week_num = 1
        current_date = start_date

        # Find first Monday
        while current_date.weekday() != 0:
            current_date += timedelta(days=1)

        while current_date <= end_date:
            day_of_week = current_date.weekday()
            date_str = current_date.strftime("%Y%m%d")
            is_past = current_date < today

            # v114: Get the correct program based on week number
            phase_idx, phase = get_phase_for_week(week_num)
            phase_name = phase["name"].lower()
            prog_id = f"prog_bobby_{quarter_id}_{phase_name}"
            phase_protocol = phase["protocol"]

            # MWF = strength (Mon=0, Wed=2, Fri=4)
            if day_of_week in [0, 2, 4]:
                workout_id = f"bobby_{date_str}_strength"
                workout_type = "strength"
                split_day = "full_body"
                variant = "A" if day_of_week == 0 else "B" if day_of_week == 2 else "C"
                workout_name = f"Week {week_num} Full Body {variant}"
                # v114: Use phase-appropriate protocol
                protocol_id = phase_protocol

            # T/Th = cardio (Tue=1, Thu=3)
            elif day_of_week in [1, 3]:
                workout_id = f"bobby_{date_str}_cardio"
                workout_type = "cardio"
                split_day = "not_applicable"
                variant = "A" if day_of_week == 1 else "B"
                workout_name = f"Week {week_num} Cardio {variant}"
                protocol_id = "cardio_30min_steady"
            else:
                # Increment week on Sunday
                if day_of_week == 6:
                    week_num += 1
                current_date += timedelta(days=1)
                continue

            # Check if workout should be skipped (only for past workouts)
            workout_skipped = is_past and should_skip_workout(current_date)

            if workout_skipped:
                workout_status = "skipped"
                total_stats["workouts_skipped"] += 1
            elif is_past:
                workout_status = "completed"
                total_stats["workouts_completed"] += 1
            else:
                workout_status = "scheduled"

            # Select exercises for this workout
            exercise_ids = select_exercises_for_workout(current_date, workout_type)

            workout_data = {
                "id": workout_id,
                "programId": prog_id,
                "name": workout_name,
                "scheduledDate": f"{current_date.isoformat()}T10:00:00Z",
                "type": workout_type,
                "splitDay": split_day,
                "status": workout_status,
                "completedDate": f"{current_date.isoformat()}T11:30:00Z" if workout_status == "completed" else None,
                "exerciseIds": exercise_ids if not workout_skipped else [],
                "protocolVariantIds": {},
            }

            # Generate instances and sets (only for non-skipped past workouts or future workouts)
            if not workout_skipped:
                for ex_idx, exercise_id in enumerate(exercise_ids):
                    instance_id = f"{workout_id}_ex{ex_idx}"

                    # Check if this exercise should be skipped
                    exercise_skipped = is_past and should_skip_exercise(current_date, ex_idx)

                    if exercise_skipped:
                        instance_status = "skipped"
                        total_stats["exercises_skipped"] += 1
                    elif is_past:
                        instance_status = "completed"
                        total_stats["exercises_completed"] += 1
                    else:
                        instance_status = "scheduled"

                    # Get protocol details
                    if workout_type == "cardio":
                        protocol = {"reps": [1], "intensity": 0.5, "rest": 0}
                        protocol_id = "cardio_30min_steady"
                        phase_intensity = 0.5
                    else:
                        protocol = PROTOCOLS.get(protocol_id, PROTOCOLS["strength_3x5_moderate"])
                        # v114: Use phase-specific intensity based on week
                        phase_intensity = get_intensity_for_week(week_num, phase)

                    # Get 1RM for this exercise at this date
                    one_rm = get_1rm_for_date(exercise_id, current_date)
                    # v114: Use phase intensity instead of protocol default
                    target_weight = round(one_rm * phase_intensity, 1)

                    # Generate set IDs
                    set_ids = []
                    for set_num in range(len(protocol["reps"])):
                        set_id = f"{instance_id}_s{set_num + 1}"
                        set_ids.append(set_id)

                        target_reps = protocol["reps"][set_num]

                        # Generate actual performance (only for past, non-skipped)
                        if is_past and instance_status == "completed":
                            actual_weight, actual_reps, set_status = generate_actual_performance(
                                target_weight, target_reps, current_date, ex_idx * 10 + set_num
                            )
                            if set_status == "skipped":
                                total_stats["sets_skipped"] += 1
                            else:
                                total_stats["sets_completed"] += 1
                        elif is_past and instance_status == "skipped":
                            actual_weight, actual_reps, set_status = None, None, "skipped"
                            total_stats["sets_skipped"] += 1
                        else:
                            actual_weight, actual_reps, set_status = None, None, "scheduled"

                        sets[set_id] = {
                            "id": set_id,
                            "exerciseInstanceId": instance_id,
                            "setNumber": set_num + 1,
                            "targetWeight": target_weight if workout_type == "strength" else None,
                            "targetReps": target_reps,
                            "actualWeight": actual_weight,
                            "actualReps": actual_reps,
                            "completion": set_status,
                            "recordedDate": f"{current_date.isoformat()}T{10 + ex_idx}:{30 + set_num * 3}:00Z" if set_status == "completed" else None,
                        }

                    # Add protocol variant ID to workout
                    workout_data["protocolVariantIds"][str(ex_idx)] = protocol_id

                    instances[instance_id] = {
                        "id": instance_id,
                        "exerciseId": exercise_id,
                        "workoutId": workout_id,
                        "protocolVariantId": protocol_id,
                        "setIds": set_ids,
                        "status": instance_status,
                        "orderIndex": ex_idx,
                    }

            workouts.append(workout_data)

            # Increment week on Sunday
            if day_of_week == 6:
                week_num += 1

            current_date += timedelta(days=1)

    return workouts, instances, sets, total_stats


def generate_targets():
    """Generate 1RM targets with history for Bobby."""
    targets = {}

    for exercise_id, values in ONE_RM_PROGRESSION.items():
        target_id = f"bobby-{exercise_id}"

        history = []
        for i, q in enumerate(QUARTERS):
            if i < len(values):
                history.append({
                    "date": f"{q['start']}T00:00:00Z",
                    "target": values[i],
                    "calibrationSource": "quarterly_test",
                })

        targets[target_id] = {
            "id": target_id,
            "memberId": "bobby",
            "exerciseId": exercise_id,
            "currentTarget": float(values[-1]),
            "targetHistory": history,
            "lastUpdated": "2025-10-31T00:00:00Z",
            "targetType": "max",
        }

    return targets


def main():
    print("=== v114: Generating Rich Historical Data for Bobby ===\n")
    print("Periodization: 3 programs per plan (Accumulation → Intensification → Realization)\n")

    # Generate all data
    plans = generate_plans()
    print(f"Generated {len(plans)} plans")

    programs = generate_programs()
    print(f"Generated {len(programs)} programs")

    print("\nGenerating workouts with performance data...")
    workouts, instances, sets, stats = generate_workouts_with_data()
    print(f"Generated {len(workouts)} workouts")
    print(f"Generated {len(instances)} exercise instances")
    print(f"Generated {len(sets)} sets")

    print(f"\n=== Performance Stats ===")
    print(f"Workouts: {stats['workouts_completed']} completed, {stats['workouts_skipped']} skipped")
    print(f"Exercises: {stats['exercises_completed']} completed, {stats['exercises_skipped']} skipped")
    print(f"Sets: {stats['sets_completed']} completed, {stats['sets_skipped']} skipped")

    targets = generate_targets()
    print(f"\nGenerated {len(targets)} target entries with history")

    # Save plans
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/plans.json", "r") as f:
        existing_plans = json.load(f)
    existing_plans = {k: v for k, v in existing_plans.items() if not k.startswith("plan_bobby")}
    existing_plans.update(plans)
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/plans.json", "w") as f:
        json.dump(existing_plans, f, indent=2)
    print("\nUpdated plans.json")

    # Save programs
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/programs.json", "r") as f:
        existing_programs = json.load(f)
    existing_programs = {k: v for k, v in existing_programs.items() if not k.startswith("prog_bobby")}
    existing_programs.update(programs)
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/programs.json", "w") as f:
        json.dump(existing_programs, f, indent=2)
    print("Updated programs.json")

    # Save workouts
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/workouts.json", "r") as f:
        existing_workouts = json.load(f)
    existing_workouts = [w for w in existing_workouts if not w["id"].startswith("bobby_")]
    existing_workouts.extend(workouts)
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/workouts.json", "w") as f:
        json.dump(existing_workouts, f, indent=2)
    print(f"Updated workouts.json ({len(existing_workouts)} total)")

    # Save instances
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/instances.json", "r") as f:
        existing_instances = json.load(f)
    existing_instances = {k: v for k, v in existing_instances.items() if not k.startswith("bobby_")}
    existing_instances.update(instances)
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/instances.json", "w") as f:
        json.dump(existing_instances, f, indent=2)
    print(f"Updated instances.json ({len(existing_instances)} total)")

    # Save sets
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/sets.json", "r") as f:
        existing_sets = json.load(f)
    existing_sets = {k: v for k, v in existing_sets.items() if not k.startswith("bobby_")}
    existing_sets.update(sets)
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/sets.json", "w") as f:
        json.dump(existing_sets, f, indent=2)
    print(f"Updated sets.json ({len(existing_sets)} total)")

    # Save targets
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/targets.json", "r") as f:
        existing_targets = json.load(f)
    for target_id, target_data in targets.items():
        existing_targets[target_id] = target_data
    with open("/Users/bobbytulsiani/Desktop/medina/Resources/Data/targets.json", "w") as f:
        json.dump(existing_targets, f, indent=2)
    print("Updated targets.json")

    print("\n=== Summary ===")
    print("Plans: Q4 2024, Q1-Q4 2025 (5 total)")
    print("Programs: 3 per plan (15 total)")
    print("  - Accumulation (weeks 1-4): 60%→70% intensity, volume focus")
    print("  - Intensification (weeks 5-8): 70%→80% intensity, strength focus")
    print("  - Realization (weeks 9-12): 80%→90% intensity, peaking")
    print(f"Workouts: {len(workouts)} (MWF strength + T/Th cardio)")
    print(f"Instances: {len(instances)} exercise instances with protocols")
    print(f"Sets: {len(sets)} with actual performance data")
    print("1RM history: 12 exercises with quarterly progression")


if __name__ == "__main__":
    main()
