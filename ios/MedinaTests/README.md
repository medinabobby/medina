# Medina Smoke Test Suite

## Purpose
Automated smoke tests to validate critical user flows before TestFlight releases.

## Test Coverage

### MihirSmokeTests
Pre-beta validation suite for Mihir's profile (47yo male, intermediate strength training).

**Test Categories:**

1. **User Profile Tests** (3 tests)
   - Profile existence and basic data
   - Age calculation from birthdate (9/11/1978 = 47yo)
   - Member profile settings (goals, experience, trainer)

2. **Plan/Program/Workout Structure** (3 tests)
   - Active plan existence
   - Program-workout hierarchy integrity
   - Scheduled date validation within plan range

3. **Library Isolation Tests** (4 tests)
   - User library existence
   - Unique exercise count (18 exercises)
   - Unique protocol count (6 protocols)
   - Library matches workout requirements

4. **Workout Execution Tests** (2 tests)
   - Exercise instances created for workouts
   - Sets defined for each instance

5. **Data Validation Tests** (3 tests)
   - Workout → Exercise reference integrity
   - Instance → Protocol reference integrity
   - Workout ↔ Instance exercise ID matching

6. **Age-Appropriate Protocol Tests** (1 test)
   - RPE ≤ 9.0 for masters athlete (47yo)
   - Adequate rest periods for high-intensity sets (≥90s)

7. **Menu Action Tests** (2 tests)
   - Scheduled workout actions (Start/Skip)
   - In-progress workout actions (Continue/End Early)

**Total: 18 smoke tests**

## Running Tests

### Command Line
```bash
./run_smoke_tests.sh
```

### Xcode
1. Open `Medina.xcodeproj`
2. Press `Cmd+U` to run all tests
3. Or: Product → Test

### Run Specific Test Class
```bash
xcodebuild test \
  -scheme Medina \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MedinaTests/MihirSmokeTests
```

### Run Single Test
```bash
xcodebuild test \
  -scheme Medina \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MedinaTests/MihirSmokeTests/testMihirProfileAge
```

## Test Results

Results are logged to `/tmp/medina_smoke_tests.log`

**Success Output:**
```
✅ All smoke tests passed!

📋 Test Summary:
   Passed: 18

🚀 Ready for TestFlight deployment to Mihir!
```

**Failure Output:**
```
❌ Some tests failed!

📋 Failed Tests:
   (List of failed test names)

📄 Full log: /tmp/medina_smoke_tests.log
```

## Pre-Beta Checklist

Before sending to Mihir via TestFlight:

- [ ] All 18 smoke tests pass
- [ ] Mihir's profile data verified (age 47, strength goal, Tue/Thu)
- [ ] Mihir's library has 18 unique exercises
- [ ] Mihir's library has 6 unique protocols
- [ ] Active plan exists with scheduled workouts
- [ ] Protocols are age-appropriate (RPE ≤ 9.0)
- [ ] Data validation rules pass
- [ ] Menu actions work correctly
- [ ] Build succeeds for TestFlight target
- [ ] TestFlight build uploaded
- [ ] Mihir invited as internal tester

## CI/CD Integration

### GitHub Actions (example)
```yaml
- name: Run Smoke Tests
  run: ./run_smoke_tests.sh
```

### Fastlane (example)
```ruby
lane :smoke_test do
  run_tests(
    scheme: "Medina",
    devices: ["iPhone 17 Pro"],
    only_testing: ["MedinaTests/MihirSmokeTests"]
  )
end
```

## Adding New Tests

1. Add test method to `MihirSmokeTests.swift`
2. Follow naming convention: `test<Scenario>()`
3. Use Given/When/Then structure in comments
4. Use descriptive assertion messages
5. Run test locally to verify
6. Update this README with new test count

## Troubleshooting

### Tests Won't Run
- Check Xcode path: `xcode-select -p`
- Should be: `/Applications/Xcode.app/Contents/Developer`
- Fix: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

### Data Not Loading
- Tests use `resetAndReload()` to get fresh JSON data
- Check JSON files in `Resources/Data/`
- Verify `LocalDataLoader.loadAll()` works

### Specific Test Failing
- Read test assertion message for details
- Check Mihir's data in JSON files
- Verify data relationships (plan → program → workout)

## Notes

- Tests use `TestDataManager.shared` with JSON data
- Each test starts with clean slate via `resetAndReload()`
- Tests are independent and can run in any order
- No network calls or async operations
- Fast execution (~1-2 seconds total)
