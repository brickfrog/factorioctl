//! Integration tests for pathfinding using fixtures

use std::fs;
use std::path::Path;

use serde::Deserialize;

use factorioctl::world::{find_belt_route, Area, CollisionMap, GridPos, Position};

#[derive(Debug, Deserialize)]
struct Fixture {
    name: String,
    #[allow(dead_code)]
    description: String,
    #[allow(dead_code)]
    source: Option<String>,
    bounds: BoundsSpec,
    blocked: Vec<BlockedSpec>,
    test_cases: Vec<TestCase>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum BlockedSpec {
    /// Simple format: just [x, y] coordinates
    Simple([i32; 2]),
    /// Verbose format with comment and multiple positions
    Verbose {
        #[allow(dead_code)]
        comment: Option<String>,
        pos: Vec<[i32; 2]>,
    },
}

#[derive(Debug, Deserialize)]
struct BoundsSpec {
    left_top: [f64; 2],
    right_bottom: [f64; 2],
}

#[derive(Debug, Deserialize)]
struct TestCase {
    name: String,
    #[allow(dead_code)]
    description: Option<String>,
    start: [i32; 2],
    goal: [i32; 2],
    expect_success: bool,
    expect_belt_count: Option<u32>,
    expect_turn_count: Option<u32>,
    expect_min_belts: Option<u32>,
    expect_turns_gte: Option<u32>,
    expect_error_contains: Option<String>,
}

fn load_fixture(name: &str) -> Fixture {
    let path = Path::new("tests/fixtures").join(format!("{}.json", name));
    let content = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("Failed to read fixture {}: {}", path.display(), e));
    serde_json::from_str(&content)
        .unwrap_or_else(|e| panic!("Failed to parse fixture {}: {}", path.display(), e))
}

fn build_collision_map(fixture: &Fixture) -> CollisionMap {
    let bounds = Area {
        left_top: Position {
            x: fixture.bounds.left_top[0],
            y: fixture.bounds.left_top[1],
        },
        right_bottom: Position {
            x: fixture.bounds.right_bottom[0],
            y: fixture.bounds.right_bottom[1],
        },
    };

    let mut map = CollisionMap::new(bounds);
    for blocked in &fixture.blocked {
        match blocked {
            BlockedSpec::Simple(pos) => {
                map.block(GridPos::new(pos[0], pos[1]));
            }
            BlockedSpec::Verbose { pos, .. } => {
                for p in pos {
                    map.block(GridPos::new(p[0], p[1]));
                }
            }
        }
    }
    map
}

fn run_fixture_tests(fixture_name: &str) {
    let fixture = load_fixture(fixture_name);
    let collision_map = build_collision_map(&fixture);

    println!("Running fixture: {}", fixture.name);

    for test_case in &fixture.test_cases {
        println!("  Test case: {}", test_case.name);

        let start = GridPos::new(test_case.start[0], test_case.start[1]);
        let goal = GridPos::new(test_case.goal[0], test_case.goal[1]);

        let result = find_belt_route(start, goal, &collision_map);

        // Check success/failure
        assert_eq!(
            result.success, test_case.expect_success,
            "Test '{}': expected success={}, got success={}, error={:?}",
            test_case.name, test_case.expect_success, result.success, result.error
        );

        if test_case.expect_success {
            // Check exact belt count if specified
            if let Some(expected) = test_case.expect_belt_count {
                assert_eq!(
                    result.belt_count, expected,
                    "Test '{}': expected {} belts, got {}",
                    test_case.name, expected, result.belt_count
                );
            }

            // Check exact turn count if specified
            if let Some(expected) = test_case.expect_turn_count {
                assert_eq!(
                    result.turn_count, expected,
                    "Test '{}': expected {} turns, got {}",
                    test_case.name, expected, result.turn_count
                );
            }

            // Check minimum belt count if specified
            if let Some(min) = test_case.expect_min_belts {
                assert!(
                    result.belt_count >= min,
                    "Test '{}': expected at least {} belts, got {}",
                    test_case.name,
                    min,
                    result.belt_count
                );
            }

            // Check minimum turns if specified
            if let Some(min) = test_case.expect_turns_gte {
                assert!(
                    result.turn_count >= min,
                    "Test '{}': expected at least {} turns, got {}",
                    test_case.name,
                    min,
                    result.turn_count
                );
            }
        } else {
            // Check error message if specified
            if let Some(expected_error) = &test_case.expect_error_contains {
                let error = result.error.as_deref().unwrap_or("");
                assert!(
                    error.contains(expected_error),
                    "Test '{}': expected error containing '{}', got '{}'",
                    test_case.name,
                    expected_error,
                    error
                );
            }
        }
    }
}

#[test]
fn test_open_area_pathfinding() {
    run_fixture_tests("open_area");
}

#[test]
fn test_single_obstacle_pathfinding() {
    run_fixture_tests("single_obstacle");
}

#[test]
fn test_real_factory_section_pathfinding() {
    run_fixture_tests("real_factory_section");
}

/// Debug test to visualize path around furnace in belt line
#[test]
fn test_visualize_path_around_furnace() {
    let fixture = load_fixture("real_factory_section");
    let collision_map = build_collision_map(&fixture);

    // Route from west side (46,-21) to east side (55,-21), must go around furnace at (50-51,-21)
    let start = GridPos::new(46, -21);
    let goal = GridPos::new(55, -21);

    let result = find_belt_route(start, goal, &collision_map);

    assert!(result.success, "Expected path to be found");

    // Collect blocked positions for validation
    let blocked: std::collections::HashSet<_> = fixture
        .blocked
        .iter()
        .flat_map(|b| match b {
            BlockedSpec::Simple(pos) => vec![*pos],
            BlockedSpec::Verbose { pos, .. } => pos.clone(),
        })
        .map(|p| (p[0], p[1]))
        .collect();

    // Verify the path doesn't go through blocked tiles
    for belt in &result.belts {
        let x = belt.position.x as i32;
        let y = belt.position.y as i32;
        assert!(
            !blocked.contains(&(x, y)),
            "Path goes through blocked tile ({}, {})",
            x,
            y
        );
    }

    // Verify path is reasonable (should be around 14 tiles with turns to go around obstacle)
    assert!(
        result.belt_count >= 10 && result.belt_count <= 20,
        "Expected belt count between 10-20, got {}",
        result.belt_count
    );
    assert!(
        result.turn_count >= 2,
        "Expected at least 2 turns to go around obstacle, got {}",
        result.turn_count
    );
}
